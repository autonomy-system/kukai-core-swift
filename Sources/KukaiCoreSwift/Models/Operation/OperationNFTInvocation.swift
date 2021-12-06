//
//  OperationNFTInvocation.swift
//  KukaiCoreSwift
//
//  Created by Ho Hien on 29/11/2021.
//

import Foundation
import os.log

/// `Operation` subclass for calling an entrypoint of a smart contract on the Tezos network
public class OperationNFTInvocation<P: Codable & Equatable>: Operation {

    /// The amount sent to the contract, usually zero, requirement of the network. Usually the amount is specified in the michelson
    public var amount: String = "0"

    /// The address of the contract that will be called
    public let destination: String

    /// Dictionary holding the `entrypoint` and `value` of the contract call
    public let parameters: P

    enum CodingKeys: String, CodingKey {
        case amount
        case destination
        case parameters
    }

    /**
    Create an OperationOrigination.
    - parameter entrypoint: A String containing the name of the entrypoint to call.
    - parameter value: A String containing the JSON Michelson/Micheline needed by the given entrypoint.
    */
    public init(source: String, amount: TokenAmount = TokenAmount.zeroBalance(decimalPlaces: 0), destinationContract: String, parameters: P) {
        self.amount = amount.rpcRepresentation
        self.destination = destinationContract
        self.parameters = parameters

        super.init(operationKind: .transaction, source: source)
    }

    /**
    Create a base operation.
    - parameter from: A decoder used to convert a data fromat (such as JSON) into the model object.
    */
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decode(String.self, forKey: .amount)
        destination = try container.decode(String.self, forKey: .destination)
        parameters = try container.decode(P.self, forKey: .parameters)

        try super.init(from: decoder)
    }

    /**
    Convert the object into a data format, such as JSON.
    - parameter to: An encoder that will allow conversions to multipel data formats.
    */
    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        try container.encode(destination, forKey: .destination)
        try container.encode(parameters, forKey: .parameters)

        try super.encode(to: encoder)
    }

    /**
    A function to check if two operations are equal.
    - parameter _: An `Operation` to compare against
    - returns: A `Bool` indicating the result.
    */
    public func isEqual(_ op: OperationNFTInvocation) -> Bool {
        let superResult = super.isEqual(self as Operation)

        return superResult
            && destination == op.destination
        && parameters == op.parameters
    }
}
