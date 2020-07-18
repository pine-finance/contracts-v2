import { web3, artifacts } from '@nomiclabs/buidler'

import assertRevert from './helpers/assertRevert'
import { sign, toAddress, ethAddress } from './helpers/account'

const BN = web3.utils.BN
const expect = require('chai').use(require('bn-chai')(BN)).expect

const UniswapEx = artifacts.require('UniswapexV2')
const ERC20 = artifacts.require('FakeERC20')
const WETH9 = artifacts.require('WETH9')
const FakeUniswapFactory = artifacts.require('FakeUniswapFactory')
const UniswapV1Factory = artifacts.require('UniswapFactory')
const UniswapV2Factory = artifacts.require('UniswapV2Factory')
const UniswapV2Router01 = artifacts.require('UniswapV2Router01')
const UniswapExchange = artifacts.require('UniswapExchange')
const LimitOrderModule = artifacts.require('LimitOrder')
const UniswapRelayer = artifacts.require('UniswapRelayer')

describe("Uniswap Relayer", () => {
  const maxBn = new BN(2).pow(new BN(256)).sub(new BN(1))

  let owner
  let user
  let anotherUser
  let fromOwner

  const never = maxBn

  const creationParams = {
    ...fromOwner,
    gas: 6e6,
    gasPrice: 21e9
  }


  // Contracts
  let token1
  let token2
  let weth
  let uniswapEx
  let uniswapV1Factory
  let uniswapV2Factory
  let uniswapV2Router
  let uniswapToken1V1
  let uniswapToken2V1
  let limitOrderModule
  let uniswapRelayer

  beforeEach(async () => {

    const accounts = await web3.eth.getAccounts()

    owner = accounts[1]
    user = accounts[2]
    anotherUser = accounts[3]
    fromOwner = { from: owner }

    // Create tokens
    weth = await WETH9.new(creationParams)
    token1 = await ERC20.new(creationParams)
    token2 = await ERC20.new(creationParams)

    // Deploy Uniswap V1
    uniswapV1Factory = await UniswapV1Factory.at(
      (await FakeUniswapFactory.new()).address
    )
    await uniswapV1Factory.createExchange(token1.address)
    await uniswapV1Factory.createExchange(token2.address)
    uniswapToken1V1 = await UniswapExchange.at(
      await uniswapV1Factory.getExchange(token1.address)
    )
    uniswapToken2V1 = await UniswapExchange.at(
      await uniswapV1Factory.getExchange(token2.address)
    )

    // Deploy Uniswap V2
    uniswapV2Factory = await UniswapV2Factory.new(owner, creationParams)
    uniswapV2Router = await UniswapV2Router01.new(uniswapV2Factory.address, weth.address, creationParams)
    await uniswapV2Factory.createPair(weth.address, token1.address)
    await uniswapV2Factory.createPair(weth.address, token2.address)

    // Deploy exchange
    uniswapEx = await UniswapEx.new(creationParams)

    // Limit Orders module
    limitOrderModule = await LimitOrderModule.new(creationParams)

    // Uniswap Relayer
    uniswapRelayer = await UniswapRelayer.new(uniswapV1Factory.address, uniswapV2Router.address, creationParams)

    await token1.setBalance(new BN(2000000000), owner)
    await token2.setBalance(new BN(2000000000), owner)

    // Add liquidity to Uniswap exchange 1
    await token1.approve(uniswapToken1V1.address, maxBn, { from: owner })
    await uniswapToken1V1.addLiquidity(0, new BN(1000000000), never, {
      from: owner,
      value: new BN(5000000000)
    })

    // Add liquidity to Uniswap exchange 2
    await token2.approve(uniswapToken2V1.address, maxBn, { from: owner })
    await uniswapToken2V1.addLiquidity(0, new BN(1000000000), never, {
      from: owner,
      value: new BN(5000000000)
    })

    // Add liquidity to pair v2
    await token1.approve(uniswapV2Router.address, maxBn, { from: owner })
    await token2.approve(uniswapV2Router.address, maxBn, { from: owner })

    await uniswapV2Router.addLiquidityETH(
      token1.address,
      new BN(1000000000),
      new BN(1000000000),
      new BN(5000000000),
      owner,
      never,
      {
        from: owner,
        value: new BN(5000000000)
      }
    )


    await uniswapV2Router.addLiquidityETH(
      token2.address,
      new BN(1000000000),
      new BN(1000000000),
      new BN(5000000000),
      owner,
      never,
      {
        from: owner,
        value: new BN(5000000000)
      }
    )
  })

  describe('Best Path', () => {
    let executeTx
    describe('ETH to Token1', () => {
      beforeEach(async () => {
        const secret = web3.utils.randomHex(32)
        const witness = toAddress(secret)

        // Create order
        const encodedOrder = await uniswapEx.encodeEthOrder(
          limitOrderModule.address,         // Limit orders module
          ethAddress,                       // ETH Address
          user,                             // Owner of the order
          witness,                          // Witness public address
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          ),
          secret                            // Witness secret
        )

        await uniswapEx.depositEth(
          encodedOrder,
          {
            value: new BN(10000),
            from: user
          }
        )

        // Sign witnesses using the secret
        const witnesses = sign(anotherUser, secret)

        // Execute order
        executeTx = async (version: number): Promise<void> => uniswapEx.executeOrder(
          limitOrderModule.address,         // Limit orders module
          ethAddress,                       // Sell ETH
          user,                             // Owner of the order
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          ),
          witnesses,                        // Witnesses of the secret
          web3.eth.abi.encodeParameters(
            ['address', 'address', 'uint8'],
            [uniswapRelayer.address, anotherUser, version]
          ),
          {
            from: anotherUser,
            gasPrice: 0
          }
        )
      })

      it('should get v1 as best path', async () => {
        // Make better rate for v1 executing an order at v2
        await executeTx(2)

        const version = await uniswapRelayer.getBestPath(
          ethAddress,                       // ETH Address
          new BN(10000),                    // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          )
        )


        await expect(version.toNumber()).to.be.equal(1)
      })

      it('should get v2 as best path', async () => {
        // Make better rate for v2 executing an order at v1
        await executeTx(1)

        const version = await uniswapRelayer.getBestPath(
          ethAddress,                       // ETH Address
          new BN(10000),                    // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          )
        )


        await expect(version.toNumber()).to.be.equal(2)
      })
    })

    describe('Token1 to ETH', () => {
      beforeEach(async () => {
        const secret = web3.utils.randomHex(32)
        const witness = toAddress(secret)

        // Encode order transfer
        const orderTx = await uniswapEx.encodeTokenOrder(
          limitOrderModule.address,     // Limit orders module
          token1.address,               // Sell token 1
          user,                         // Owner of the order
          witness,                      // Witness address
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              ethAddress,               // Buy ETH
              new BN(50),               // Get at least 50 ETH Wei
              new BN(15)                // Pay 15 WEI to sender
            ]
          ),
          secret,                       // Witness secret
          new BN(10000)                 // Tokens to sell
        )

        await uniswapEx.vaultOfOrder(
          limitOrderModule.address,     // Limit orders module
          token1.address,               // Sell token 1
          user,                         // Owner of the order
          witness,                      // Witness address
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              ethAddress,               // Buy ETH
              new BN(50),               // Get at least 50 ETH Wei
              new BN(15)                // Pay 15 WEI to sender
            ]
          )
        )

        await token1.setBalance(new BN(10000), user)

        // Send tokens tx
        await web3.eth.sendTransaction({
          from: user,
          to: token1.address,
          data: orderTx,
          gasPrice: 0
        })

        // Sign witnesses using the secret
        const witnesses = sign(anotherUser, secret)

        // Execute order
        executeTx = async (version: number): Promise<void> => uniswapEx.executeOrder(
          limitOrderModule.address,     // Limit orders module
          token1.address,               // Sell token 1
          user,                         // Owner of the order
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              ethAddress,               // Buy ETH
              new BN(50),               // Get at least 50 ETH Wei
              new BN(15)                // Pay 15 WEI to sender
            ]
          ),
          witnesses,                    // Witnesses, sender signed using the secret
          web3.eth.abi.encodeParameters(
            ['address', 'address', 'uint8'],
            [uniswapRelayer.address, anotherUser, version]
          ),
          {
            from: anotherUser,
            gasPrice: 0
          }
        )
      })

      it('should get v1 as best path', async () => {
        // Make better rate for v1 executing an order at v2
        await executeTx(2)

        const version = await uniswapRelayer.getBestPath(
          token1.address,                       // Token1 Address
          new BN(10000),                        // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              ethAddress,                       // Buy ETH
              new BN(50),                       // Get at least 50 ETH Wei
              new BN(15)                        // Pay 15 WEI to sender
            ]
          )
        )


        await expect(version.toNumber()).to.be.equal(1)
      })

      it('should get v2 as best path', async () => {
        // Make better rate for v2 executing an order at v1
        await executeTx(1)

        const version = await uniswapRelayer.getBestPath(
          token1.address,                       // Token1 Address
          new BN(10000),                        // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              ethAddress,                       // Buy ETH
              new BN(50),                       // Get at least 50 ETH Wei
              new BN(15)                        // Pay 15 WEI to sender
            ]
          )
        )


        await expect(version.toNumber()).to.be.equal(2)
      })
    })

    describe('Token1 To Token2', () => {
      beforeEach(async () => {
        executeTx = async (version: number): Promise<void> => {
          const secret = web3.utils.randomHex(32)
          const witness = toAddress(secret)

          // Encode order transfer
          const orderTx = await uniswapEx.encodeTokenOrder(
            limitOrderModule.address,     // Limit orders module
            token1.address,               // Sell token 1
            user,                         // Owner of the order
            witness,                      // Witness address
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'uint256'],
              [
                token2.address,           // Buy TOKEN 2
                new BN(50),               // Get at least 50 ETH Wei
                new BN(9)                 // Pay 9 WEI to sender
              ]
            ),
            secret,                       // Witness secret
            new BN(10000)                 // Tokens to sell
          )

          await uniswapEx.vaultOfOrder(
            limitOrderModule.address,     // Limit orders module
            token1.address,               // Sell token 1
            user,                         // Owner of the order
            witness,                      // Witness address
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'uint256'],
              [
                token2.address,           // Buy TOKEN 2
                new BN(50),               // Get at least 50 ETH Wei
                new BN(9)                 // Pay 9 WEI to sender
              ]
            )
          )

          await token1.setBalance(new BN(10000), user)

          // Send tokens tx
          await web3.eth.sendTransaction({
            from: user,
            to: token1.address,
            data: orderTx,
            gasPrice: 0
          })

          const witnesses = sign(anotherUser, secret)

          // Execute order
          await uniswapEx.executeOrder(
            limitOrderModule.address,     // Limit orders module
            token1.address,               // Sell token 1
            user,                         // Owner of the order
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'uint256'],
              [
                token2.address,           // Buy TOKEN 2
                new BN(50),               // Get at least 50 ETH Wei
                new BN(9)                 // Pay 9 WEI to sender
              ]
            ),
            witnesses,                    // Witnesses, sender signed using the secret
            web3.eth.abi.encodeParameters(
              ['address', 'address', 'uint8'],
              [uniswapRelayer.address, anotherUser, version]
            ),
            {
              from: anotherUser,
              gasPrice: 0
            }
          )
        }
      })

      it('should get v1 as best path', async () => {
        // Make better rate for v1 executing an order at v2
        await executeTx(2)

        const version = await uniswapRelayer.getBestPath(
          token1.address,                       // Token1 Address
          new BN(10000),                        // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token2.address,                   // Buy TOKEN 2
              new BN(50),                       // Get at least 50 ETH Wei
              new BN(9)                         // Pay 9 WEI to sender
            ]
          )
        )

        await expect(version.toNumber()).to.be.equal(1)
      })

      it('should get v2 as best path', async () => {
        // Make better rate for v2 executing an order at v1
        await executeTx(1)
        await executeTx(1)
        await executeTx(1)
        await executeTx(1)

        const version = await uniswapRelayer.getBestPath(
          token1.address,                       // Token1 Address
          new BN(10000),                        // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token2.address,                 // Buy TOKEN 2
              new BN(50),                     // Get at least 50 ETH Wei
              new BN(9)                       // Pay 9 WEI to sender
            ]
          )
        )

        await expect(version.toNumber()).to.be.equal(2)
      })
    })

    describe('Change', () => {
      beforeEach(async () => {
        executeTx = async (version: number): Promise<any> => {
          const secret = web3.utils.randomHex(32)
          const witness = toAddress(secret)

          // Create order
          const encodedOrder = await uniswapEx.encodeEthOrder(
            limitOrderModule.address,         // Limit orders module
            ethAddress,                       // ETH Address
            user,                             // Owner of the order
            witness,                          // Witness public address
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'uint256'],
              [
                token1.address,               // Buy TOKEN 1
                new BN(300),                  // Get at least 300 Tokens
                new BN(10)                    // Pay 10 WEI to sender
              ]
            ),
            secret                            // Witness secret
          )

          await uniswapEx.depositEth(
            encodedOrder,
            {
              value: new BN(100000),
              from: user
            }
          )

          // Sign witnesses using the secret
          const witnesses = sign(anotherUser, secret)

          // Execute order
          return uniswapEx.executeOrder(
            limitOrderModule.address,         // Limit orders module
            ethAddress,                       // Sell ETH
            user,                             // Owner of the order
            web3.eth.abi.encodeParameters(
              ['address', 'uint256', 'uint256'],
              [
                token1.address,               // Buy TOKEN 1
                new BN(300),                  // Get at least 300 Tokens
                new BN(10)                    // Pay 10 WEI to sender
              ]
            ),
            witnesses,                        // Witnesses of the secret
            web3.eth.abi.encodeParameters(
              ['address', 'address', 'uint8'],
              [uniswapRelayer.address, anotherUser, version]
            ),
            {
              from: anotherUser,
              gasPrice: 0
            }
          )
        }
      })

      it('should change best path', async () => {
        // Make better rate for v1 executing an order at v2
        await executeTx(2)

        let version = await uniswapRelayer.getBestPath(
          ethAddress,                       // ETH Address
          new BN(100000),                    // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          )
        )

        expect(version.toNumber()).to.be.equal(1)

        // Make better rate for v2 executing an order at v1
        await executeTx(1)
        await executeTx(1)
        await executeTx(1)

        version = await uniswapRelayer.getBestPath(
          ethAddress,                       // ETH Address
          new BN(100000),                   // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          )
        )

        expect(version.toNumber()).to.be.equal(2)

        // Make better rate for v1 executing an order at v2
        await executeTx(2)
        await executeTx(2)

        version = await uniswapRelayer.getBestPath(
          ethAddress,                       // ETH Address
          new BN(100000),                   // Input Amount
          web3.eth.abi.encodeParameters(
            ['address', 'uint256', 'uint256'],
            [
              token1.address,               // Buy TOKEN 1
              new BN(300),                  // Get at least 300 Tokens
              new BN(10)                    // Pay 10 WEI to sender
            ]
          )
        )

        expect(version.toNumber()).to.be.equal(1)
      })
    })
  })

  it('should return 0 for not ready paths', async () => {
    const version = await uniswapRelayer.getBestPath(
      token1.address,                       // Token1 Address
      new BN(1000),                         // Input Amount
      web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'uint256'],
        [
          token2.address,                 // Buy TOKEN 2
          new BN(500000),                     // Get at least 50 ETH Wei
          new BN(9)                       // Pay 9 WEI to sender
        ]
      )
    )


    await expect(version.toNumber()).to.be.equal(0)
  })

  it('reverts for invalid operations', async () => {
    await assertRevert(uniswapRelayer.getBestPath(
      user,                       // Token1 Address
      new BN(1000),                         // Input Amount
      web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'uint256'],
        [
          token2.address,                 // Buy TOKEN 2
          new BN(500000),                     // Get at least 50 ETH Wei
          new BN(9)                       // Pay 9 WEI to sender
        ]
      )
    ))
  })
})