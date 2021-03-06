//
//  SignUtils.swift
//  zrxkit
//
//  Created by Abai Abakirov on 10/25/19.
//  Copyright © 2019 BlocksDecoded. All rights reserved.
//

import Foundation
import Web3

public class SignUtils {
  private let V_INDEX = 0
  private let R_RANGE = 1...32
  private let S_RANGE = 33...64
  
  public init() {}
  
  private let types: [String: [Eip712Data.Entry]] = [
    "EIP712Domain": [
      Eip712Data.Entry(name: "name", type: "string"),
      Eip712Data.Entry(name: "version", type: "string"),
      Eip712Data.Entry(name: "chainId", type: "uint256"),
      Eip712Data.Entry(name: "verifyingContract", type: "address")
    ],
    "Order": [
      Eip712Data.Entry(name: "makerAddress", type: "address"),
      Eip712Data.Entry(name: "takerAddress", type: "address"),
      Eip712Data.Entry(name: "feeRecipientAddress", type: "address"),
      Eip712Data.Entry(name: "senderAddress", type: "address"),
      Eip712Data.Entry(name: "makerAssetAmount", type: "uint256"),
      Eip712Data.Entry(name: "takerAssetAmount", type: "uint256"),
      Eip712Data.Entry(name: "makerFee", type: "uint256"),
      Eip712Data.Entry(name: "takerFee", type: "uint256"),
      Eip712Data.Entry(name: "expirationTimeSeconds", type: "uint256"),
      Eip712Data.Entry(name: "salt", type: "uint256"),
      Eip712Data.Entry(name: "makerAssetData", type: "bytes"),
      Eip712Data.Entry(name: "takerAssetData", type: "bytes"),
      Eip712Data.Entry(name: "makerFeeAssetData", type: "bytes"),
      Eip712Data.Entry(name: "takerFeeAssetData", type: "bytes")
    ]
  ]
  
  private func getOrderSignature(_ order: IOrder, _ privateKey: EthereumPrivateKey) -> String {
    let structured = Eip712Data.EIP712Message(types: types, primaryType: "Order", message: orderToMap(order), domain: getDomain(order))
    let encoder = Eip712Encoder(structured)
    
    try! encoder.validateStructuredData(structured)
    
    let eipOrder = encoder.hashStructuredData()
    
    let result = try! privateKey.sign(message: eipOrder)

    var resultArray = [UInt8]()
    resultArray.append(UInt8(result.v) + 27)
    resultArray.append(contentsOf: result.r)
    resultArray.append(contentsOf: result.s)
    resultArray.append(2)
    
    return resultArray.toHexString().prefixed()
  }
  
  internal func signedMessageHashToKey(_ messageHash: Bytes, _ signatureData: (v: UInt, r: Bytes, s: Bytes)) -> BigUInt {
    let r = signatureData.r
    let s = signatureData.s
    
    guard r.count == 32 else {
      fatalError("r must be 32 bytes")
    }
    
    guard s.count == 32 else {
      fatalError("s must be 32 bytes")
    }
    
    let header = signatureData.v & 0xFF
    
    if header < 27 || header > 34 {
      fatalError("Header byte out of range \(header)")
    }
    
    // TODO: Complete verify
    
    return BigUInt()
  }
  
  private func orderToMap(_ order: IOrder) -> [String: Any] {
    return [
      "makerAddress": order.makerAddress,
      "takerAddress": order.takerAddress,
      "feeRecipientAddress": order.feeRecipientAddress,
      "senderAddress": order.senderAddress,
      "makerAssetAmount": order.makerAssetAmount.toBigUInt(),
      "takerAssetAmount": order.takerAssetAmount.toBigUInt(),
      "makerFee": order.makerFee.toBigUInt(),
      "takerFee": order.takerFee.toBigUInt(),
      "expirationTimeSeconds": order.expirationTimeSeconds.toBigUInt(),
      "salt": order.salt.toBigUInt(),
      "makerAssetData": order.makerAssetData.clearPrefix().hexToBytes(),
      "takerAssetData": order.takerAssetData.clearPrefix().hexToBytes(),
      "makerFeeAssetData": order.makerFeeAssetData.clearPrefix().hexToBytes(),
      "takerFeeAssetData": order.takerFeeAssetData.clearPrefix().hexToBytes()
    ]
  }
  
  private func getDomain(_ order: IOrder) -> Eip712Data.EIP712Domain {
    return Eip712Data.EIP712Domain(name: "0x Protocol", version: "3.0.0", chainId: order.chainId, verifyingContract: order.exchangeAddress)
  }
  
  public func ecSignOrder(_ order: Order, _ privateKey: EthereumPrivateKey) -> SignedOrder? {
    let signature = getOrderSignature(order, privateKey)
    let signedOrder = SignedOrder.fromOrder(order: order, signature: signature)
    return signedOrder
  }
  
  func getSignatureType(_ signatureHex: String) -> ESignatureType {
    let type = signatureHex.clearPrefix().hexToBytes().last!
    switch type {
    case 2:
      return .EIP712
    case 3:
      return .ETH_SIGN
    default:
      fatalError("Unsupported Signature Type")
    }
  }
}
