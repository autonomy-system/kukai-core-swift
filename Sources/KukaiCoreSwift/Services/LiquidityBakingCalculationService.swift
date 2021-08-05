//
//  LiquidityBakingCalculationService.swift
//  KukaiCoreSwift
//
//  Created by Simon Mcloughlin on 26/11/2020.
//  Copyright © 2021 Kukai AB. All rights reserved.
//

import Foundation
import JavaScriptCore
import os.log

/// A struct to hold all the necessary calculations for a LiquidityBaking trade
public struct LiquidityBakingCalculationResult {
	public let expected: TokenAmount
	public let minimum: TokenAmount
	public let displayExchangeRate: Decimal
	public let displayPriceImpact: Double
	
	public init(expected: TokenAmount, minimum: TokenAmount, displayExchangeRate: Decimal, displayPriceImpact: Double) {
		self.expected = expected
		self.minimum = minimum
		self.displayExchangeRate = displayExchangeRate
		self.displayPriceImpact = displayPriceImpact
	}
}

/// Wrapper around the LiquidityBaking JS library for performing calculations: https://gitlab.com/sophiagold/dexter-calculations/-/tree/liquidity_baking
public class LiquidityBakingCalculationService {
	
	private let jsContext: JSContext
	
	/// Public shared instace to avoid having multiple copies of the underlying `JSContext` created
	public static let shared = LiquidityBakingCalculationService()
	
	
	private init() {
		jsContext = JSContext()
		jsContext.exceptionHandler = { context, exception in
			os_log("JSContext exception: %@", log: .kukaiCoreSwift, type: .error, exception?.toString() ?? "")
		}
		
		if let jsSourcePath = Bundle.module.url(forResource: "liquidity-baking-calcualtions", withExtension: "js", subdirectory: "External") {
			do {
				let jsSourceContents = try String(contentsOf: jsSourcePath)
				self.jsContext.evaluateScript(jsSourceContents)
				
			} catch (let error) {
				os_log("Error parsing LiquidityBaking javascript file: %@", log: .kukaiCoreSwift, type: .error, "\(error)")
			}
		}
	}
	
	
	
	// MARK: - User flow functions
	
	/**
	A helper function to create all the necessary calculations for a xtzToToken exchange, to perform the operation and display the info to the user in a confirmation screen.
	- parameter xtzToSell: The `XTZAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking contract holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking contract holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- parameter maxSlippage: `Double` containing the max slippage a user will accept for their trade.
	- returns: `LiquidityBakingCalculationResult` containing the results of all the necessary calculations.
	*/
	public func calculateXtzToToken(xtzToSell: XTZAmount, xtzPool: XTZAmount, tokenPool: TokenAmount, maxSlippage: Double) -> LiquidityBakingCalculationResult? {
		guard let expected = xtzToTokenExpectedReturn(xtzToSell: xtzToSell, xtzPool: xtzPool, tokenPool: tokenPool),
			  let minimum = xtzToTokenMinimumReturn(tokenAmount: expected, slippage: maxSlippage),
			  let rate = xtzToTokenExchangeRateDisplay(xtzToSell: xtzToSell, xtzPool: xtzPool, tokenPool: tokenPool),
			  let priceImpact = xtzToTokenPriceImpact(xtzToSell: xtzToSell, xtzPool: xtzPool, tokenPool: tokenPool) else {
			return nil
		}
		
		let impactDouble = Double(priceImpact.description) ?? 0
		
		return LiquidityBakingCalculationResult(expected: expected, minimum: minimum, displayExchangeRate: rate, displayPriceImpact: impactDouble)
	}
	
	/**
	A helper function to create all the necessary calculations for a tokenToXtz exchange, to perform the operation and display the info to the user in a confirmation screen.
	- parameter tokenToSell: The `TokenAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking contract holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking contract holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- parameter maxSlippage: `Double` containing the max slippage a user will accept for their trade.
	- returns: `LiquidityBakingCalculationResult` containing the results of all the necessary calculations.
	*/
	public func calcualteTokenToXTZ(tokenToSell: TokenAmount, xtzPool: XTZAmount, tokenPool: TokenAmount, maxSlippage: Double) -> LiquidityBakingCalculationResult? {
		guard let expected = tokenToXtzExpectedReturn(tokenToSell: tokenToSell, xtzPool: xtzPool, tokenPool: tokenPool),
			  let minimum = tokenToXtzMinimumReturn(xtzAmount: expected, slippage: maxSlippage),
			  let rate = tokenToXtzExchangeRateDisplay(tokenToSell: tokenToSell, xtzPool: xtzPool, tokenPool: tokenPool),
			  let priceImpact = tokenToXtzPriceImpact(tokenToSell: tokenToSell, xtzPool: xtzPool, tokenPool: tokenPool) else {
			return nil
		}
		
		let impactDouble = Double(priceImpact.description) ?? 0
		
		return LiquidityBakingCalculationResult(expected: expected, minimum: minimum, displayExchangeRate: rate, displayPriceImpact: impactDouble)
	}
	
	
	
	
	// MARK: - XTZ To Token
	
	/**
	The `TokenAmount` expected to be returned for the supplied `XTZAmount`, given the LiquidityBaking contract xtzPool and tokenPool.
	- parameter xtzToSell: The `XTZAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `TokenAmount` containing the amount the user can expect in return for their XTZ
	*/
	public func xtzToTokenExpectedReturn(xtzToSell: XTZAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> TokenAmount? {
		let xtz = xtzToSell.rpcRepresentation
		let xPool = xtzPool.rpcRepresentation
		let tPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenTokenOutput"),
			  let result = inner.call(withArguments: [xtz, xPool, tPool]) else {
			return nil
		}
		
		return TokenAmount(fromRpcAmount: result.toString(), decimalPlaces: tokenPool.decimalPlaces)
	}
	
	
	/**
	The minimum possible `TokenAmount` returned, taking into account slippage.
	- parameter tokenAmount: The `TokenAmount` returned from `xtzToTokenExpectedReturn()`.
	- parameter slippage: A double value between 0 and 1, indicating the maximum percentage of slippage a user will accept.
	- returns: `TokenAmount` containing the minimum amount the user can expect in return for their XTZ
	*/
	public func xtzToTokenMinimumReturn(tokenAmount: TokenAmount, slippage: Double) -> TokenAmount? {
		let token = tokenAmount.rpcRepresentation
		
		guard slippage >= 0, slippage <= 1 else {
			os_log("slippage value supplied to `xtzToTokenMinimumReturn` was not between 0 and 1: %@", log: .kukaiCoreSwift, type: .error, slippage)
			return nil
		}
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenMinimumTokenOutput"),
			  let result = inner.call(withArguments: [token, slippage]) else {
			return nil
		}
		
		return TokenAmount(fromRpcAmount: result.toString(), decimalPlaces: tokenAmount.decimalPlaces)
	}
	
	
	/**
	Calculate the `XTZAmount` required in order to receive the supplied `TokenAmount`.
	- parameter tokenAmount: The `TokenAmount` the user wants to receive.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `XTZAmount` containing the amount of XTZ required in order to recieve the amount of token.
	*/
	public func xtzToTokenRequiredXtzFor(tokenAmount: TokenAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> XTZAmount? {
		let tokenRequired = tokenAmount.rpcRepresentation
		let xtzPool = xtzPool.rpcRepresentation
		let tokenPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenXtzInput"),
			  let result = inner.call(withArguments: [tokenRequired, xtzPool, tokenPool, tokenAmount.decimalPlaces]) else {
			return nil
		}
		
		return XTZAmount(fromRpcAmount: result.toString())
	}
	
	
	
	// MARK: XTZ To Token Rates
	
	/**
	The exchange rate for a given trade, taking into account slippage and fees
	- parameter xtzToSell: The `XTZAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the exchange rate from 1 XTZ to the requested `Token`
	*/
	public func xtzToTokenExchangeRate(xtzToSell: XTZAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let xtz = xtzToSell.rpcRepresentation
		let xtzPool = xtzPool.rpcRepresentation
		let tokenPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenExchangeRate"),
			  let result = inner.call(withArguments: [xtz, xtzPool, tokenPool]) else {
			return nil
		}
		
		return Decimal(string: result.toString())
	}
	
	
	/**
	The exchange rate for a given trade, taking into account slippage and fees, formatted and truncated for easier display in the UI.
	- parameter xtzToSell: The `XTZAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the exchange rate from 1 XTZ to the requested `Token`
	*/
	public func xtzToTokenExchangeRateDisplay(xtzToSell: XTZAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let xtz = xtzToSell.rpcRepresentation
		let xPool = xtzPool.rpcRepresentation
		let tPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenExchangeRateForDisplay"),
			  let result = inner.call(withArguments: [xtz, xPool, tPool, tokenPool.decimalPlaces]) else {
			return nil
		}
		
		return Decimal(string: result.toString())?.rounded(scale: tokenPool.decimalPlaces, roundingMode: .bankers)
	}
	
	/**
	Before a user has entered in an amount to trade, its useful to show them the base exchange rate, ignoring slippage.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the exchange rate from 1 XTZ to the requested `Token`
	*/
	public func xtzToTokenMarketRate(xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let xPool = xtzPool.rpcRepresentation
		let tPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenMarketRate"),
			  let result = inner.call(withArguments: [xPool, tPool, tokenPool.decimalPlaces]) else {
			return nil
		}
		
		return Decimal(string: result.toString())?.rounded(scale: tokenPool.decimalPlaces, roundingMode: .bankers)
	}
	
	
	
	/**
	Calcualte the percentage the price impact the given trade would incur. Since this is already taken into account for the other functions, this function returns in the scale of 0 - 100, for display purposes.
	- parameter xtzToSell: The `XTZAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the slippage percentage, 0 - 100.
	*/
	public func xtzToTokenPriceImpact(xtzToSell: XTZAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let xtz = xtzToSell.rpcRepresentation
		let xtzPool = xtzPool.rpcRepresentation
		let tokenPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("xtzToTokenPriceImpact"),
			  let result = inner.call(withArguments: [xtz, xtzPool, tokenPool]) else {
			return nil
		}
		
		return (Decimal(string: result.toString())?.rounded(scale: 4, roundingMode: .bankers) ?? 0) * 100
	}
	
	
	
	// MARK: Token to XTZ
	
	/**
	The `XTZAmount` expected to be returned for the supplied `TokenAmount`, given the LiquidityBaking contracts xtzPool and tokenPool.
	- parameter tokenToSell: The `TokenAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `XTZAmount` containing the amount the user can expect in return for their `Token`
	*/
	public func tokenToXtzExpectedReturn(tokenToSell: TokenAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> XTZAmount? {
		let token = tokenToSell.rpcRepresentation
		let xtzPool = xtzPool.rpcRepresentation
		let tokenPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzXtzOutput"),
			  let result = inner.call(withArguments: [token, xtzPool, tokenPool]) else {
			return nil
		}
		
		return XTZAmount(fromRpcAmount: result.toString())
	}
	
	
	/**
	The minimum possible `XTZAmount` returned, taking into account slippage.
	- parameter xtzAmount: The `XTZAmount` returned from `tokenToXtzExpectedReturn()`.
	- parameter slippage: A double value between 0 and 1, indicating the maximum percentage of slippage a user will accept.
	- returns: `XTZAmount` containing the minimum amount the user can expect in return for their Token
	*/
	public func tokenToXtzMinimumReturn(xtzAmount: XTZAmount, slippage: Double) -> XTZAmount? {
		let xtz = xtzAmount.rpcRepresentation
		
		guard slippage >= 0, slippage <= 1 else {
			os_log("slippage value supplied to `tokenToXtzMinimumReturn` was not between 0 and 1: %@", log: .kukaiCoreSwift, type: .error, slippage)
			return nil
		}
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzMinimumXtzOutput"),
			  let result = inner.call(withArguments: [xtz, slippage]) else {
			return nil
		}
		
		return XTZAmount(fromRpcAmount: result.toString())
	}
	
	
	/**
	Calculate the `TokenAmount` required in order to receive the supplied `XTZAmount`.
	- parameter xtzAmount: The `XTZAmount` the user wants to receive.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `TokenAmount` containing the amount of `Token` required in order to recieve the amount of XTZ.
	*/
	public func tokenToXtzRequiredTokenFor(xtzAmount: XTZAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> TokenAmount? {
		let xtzRequired = xtzAmount.rpcRepresentation
		let xPool = xtzPool.rpcRepresentation
		let tPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzTokenInput"),
			  let result = inner.call(withArguments: [xtzRequired, xPool, tPool, tokenPool.decimalPlaces]) else {
			return nil
		}
		
		return TokenAmount(fromRpcAmount: result.toString(), decimalPlaces: tokenPool.decimalPlaces)
	}
	
	
	
	// MARK: XTZ To Token Rates
	
	/**
	The exchange rate for a given trade, taking into account slippage and fees
	- parameter tokenToSell: The `TokenAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the exchange rate from 1 of the given `Token` to XTZ
	*/
	public func tokenToXtzExchangeRate(tokenToSell: TokenAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let token = tokenToSell.rpcRepresentation
		let xtzPool = xtzPool.rpcRepresentation
		let tokenPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzExchangeRate"),
			  let result = inner.call(withArguments: [token, xtzPool, tokenPool]) else {
			return nil
		}
		
		return Decimal(string: result.toString())
	}
	
	
	/**
	The exchange rate for a given trade, taking into account slippage and fees, formatted and truncated for easier display in the UI.
	- parameter tokenToSell: The `TokenAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the exchange rate from 1 of the given `Token` to XTZ
	*/
	public func tokenToXtzExchangeRateDisplay(tokenToSell: TokenAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let token = tokenToSell.rpcRepresentation
		let xPool = xtzPool.rpcRepresentation
		let tPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzExchangeRateForDisplay"),
			  let result = inner.call(withArguments: [token, xPool, tPool, tokenPool.decimalPlaces]) else {
			return nil
		}
		
		return Decimal(string: result.toString())?.rounded(scale: tokenPool.decimalPlaces, roundingMode: .bankers)
	}
	
	
	/**
	Before a user has entered in an amount to trade, its useful to show them the base exchange rate, ignoring slippage.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the exchange rate from 1 of the given `Token` to XTZ
	*/
	public func tokenToXtzMarketRate(xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let xPool = xtzPool.rpcRepresentation
		let tPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzMarketRate"),
			  let result = inner.call(withArguments: [xPool, tPool, tokenPool.decimalPlaces]) else {
			return nil
		}
		
		return Decimal(string: result.toString())?.rounded(scale: tokenPool.decimalPlaces, roundingMode: .bankers)
	}
	
	
	/**
	Calcualte the percentage slippage the given trade would incur. Since this is already taken into account for the other functions, this function returns in the scale of 0 - 100, for display purposes.
	- parameter tokenToSell: The `TokenAmount` to sell.
	- parameter xtzPool: The `XTZAmount` representing the current pool of XTZ that the LiquidityBaking holds. Can be fetched with xxxxx.
	- parameter tokenPool: The `TokenAmount` representing the current pool of the given `Token` that the LiquidityBaking holds. Must have the same number of decimalPlaces as the token it represents. Can be fetched with xxxxx.
	- returns: `Decimal` containing the slippage percentage, 0 - 100.
	*/
	public func tokenToXtzPriceImpact(tokenToSell: TokenAmount, xtzPool: XTZAmount, tokenPool: TokenAmount) -> Decimal? {
		let token = tokenToSell.rpcRepresentation
		let xtzPool = xtzPool.rpcRepresentation
		let tokenPool = tokenPool.rpcRepresentation
		
		guard let outer = jsContext.objectForKeyedSubscript("dexterCalculations"),
			  let inner = outer.objectForKeyedSubscript("tokenToXtzPriceImpact"),
			  let result = inner.call(withArguments: [token, xtzPool, tokenPool]) else {
			return nil
		}
		
		return (Decimal(string: result.toString())?.rounded(scale: 4, roundingMode: .bankers) ?? 0) * 100
	}
}