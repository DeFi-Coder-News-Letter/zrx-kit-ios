import Foundation
import RxSwift
import Web3

public class Contract: GenericERC20Contract {
  
  let privateKey: EthereumPrivateKey
  let networkType: ZrxKit.NetworkType
  let gasProvider: ContractGasProvider
  
  private var onEventCallback: ((SolidityEmittedEvent) -> Void)?
  private var onReceiptCallback: ((EthereumTransactionReceiptObject) -> Void)?
  private var watchingEvents: [SolidityEvent]?
  
  init(
    address: EthereumAddress,
    eth: Web3.Eth,
    privateKey: EthereumPrivateKey,
    gasProvider: ContractGasProvider,
    networkType: ZrxKit.NetworkType
  )
  {
    self.privateKey = privateKey
    self.networkType = networkType
    self.gasProvider = gasProvider
    super.init(address: address, eth: eth)
  }
  
  required init(address: EthereumAddress?, eth: Web3.Eth) {
    fatalError("init(address:eth:) has not been implemented")
  }
  
  func read<T>(method: SolidityInvocation, onParse: @escaping([String: Any]) -> T) -> Observable<T> {
    return Observable.create { observer in
      method.call(completion: { (response, error) in
        if error != nil {
          observer.onError(error!)
        } else if response != nil {
          observer.onNext(onParse(response!))
        } else {
          observer.onError(ZrxError.emptyResponse)
        }
        observer.onCompleted()
      })
      return Disposables.create()
    }
  }
  
  func executeTransaction(
    invocation: SolidityInvocation?,
    value: EthereumQuantity?,
    watchEvents: [SolidityEvent]? = nil,
    data: EthereumData = EthereumData([]),
    onReceipt: ((EthereumTransactionReceiptObject) -> Void)? = nil,
    onEvent: ((SolidityEmittedEvent) -> Void)? = nil
  ) -> Observable<EthereumData>
  {
    return executeTransaction(invocation: invocation,
                              value: value,
                              address: address!,
                              watchEvents: watchEvents,
                              data: data,
                              onReceipt: onReceipt,
                              onEvent: onEvent)
  }
  
  func executeTransaction(
    invocation: SolidityInvocation?,
    value: EthereumQuantity?,
    address: EthereumAddress,
    watchEvents: [SolidityEvent]? = nil,
    data: EthereumData = EthereumData([]),
    onReceipt: ((EthereumTransactionReceiptObject) -> Void)? = nil,
    onEvent: ((SolidityEmittedEvent) -> Void)? = nil
  ) -> Observable<EthereumData>
  {
    onReceiptCallback = onReceipt
    onEventCallback = onEvent
    watchingEvents = watchEvents
    return Observable.create { observer in
      self.eth.getTransactionCount(address: self.privateKey.address, block: .latest, response: { (nonce) in
        switch nonce.status {
        case .success(let result):
          guard let transaction = self.createTransaction(invocation: invocation, value: value, nonce: result, address: address, data: data) else {
            observer.onError(ZrxError.cannotCreateTransaction)
            return
          }
          do {
            let signedTransaction = try transaction.sign(with: self.privateKey, chainId: EthereumQuantity(quantity: BigUInt(self.networkType.id)))
            self.eth.sendRawTransaction(transaction: signedTransaction, response: { (hashResponse) in
              switch hashResponse.status {
              case .success(let result):
                if self.watchingEvents != nil {
                  let watcher = TransactionWatcher(transactionHash: result, eth: self.eth)
                  watcher.delegate = self
                  watcher.startWatching(events: self.watchingEvents!)
                }
                observer.onNext(result)
                observer.onCompleted()
              case .failure(let error):
                observer.onError(error)
              }
            })
          } catch {
            observer.onError(error)
          }
        case .failure(let error):
          observer.onError(error)
        }
      })
      return Disposables.create()
    }
  }
  
  private func createTransaction(
    invocation: SolidityInvocation?,
    value: EthereumQuantity?,
    nonce: EthereumQuantity,
    address: EthereumAddress,
    data: EthereumData
  ) -> EthereumTransaction?
  {
    if invocation != nil {
      return invocation!.createTransaction(
        nonce: nonce,
        from: self.privateKey.address,
        value: value,
        gas: EthereumQuantity(quantity: gasProvider.getGasLimit(invocation!.method.name)),
        gasPrice: EthereumQuantity(quantity: gasProvider.getGasPrice(invocation!.method.name)))
    }
    return EthereumTransaction(
      nonce: nonce,
      gasPrice: EthereumQuantity(quantity: gasProvider.getGasPrice()),
      gas: EthereumQuantity(quantity: gasProvider.getGasLimit()),
      to: address,
      value: value ?? 0,
      data: data)
  }
}

extension Contract: TransactionWatcherDelegate {
  public func transactionWatcher(_ transactionWatcher: TransactionWatcher, didUpdateStatus status: TransactionWatcher.Status) {
    print("\(#file) didUpdateStatus \(status)")
  }
  
  public func transactionWatcher(_ transactionWatcher: TransactionWatcher, didReceiveReceipt receipt: EthereumTransactionReceiptObject) {
    DispatchQueue.main.async {
      self.onReceiptCallback?(receipt)
    }
  }
  
  public func transactionWatcher(_ transactionWatcher: TransactionWatcher, didReceiveEvent event: SolidityEmittedEvent) {
    print("\(#file) didReceiveEvent \(event)")
    DispatchQueue.main.async {
      self.onEventCallback?(event)
    }
    if watchingEvents != nil {
      transactionWatcher.stopWatching(events: watchingEvents!)
    }
  }
}
