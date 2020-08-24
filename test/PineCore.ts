import { web3, artifacts } from '@nomiclabs/buidler'

import { balanceSnap, etherSnap } from './helpers/balanceSnap'
import { sign, toAddress, ethAddress } from './helpers/account'
import assertRevert from './helpers/assertRevert'

const BN = web3.utils.BN
const expect = require('chai').use(require('bn-chai')(BN)).expect

const ERC20 = artifacts.require('FakeERC20')
const PineCore = artifacts.require('PineCore')
const VaultFactory = artifacts.require('VaultFactory')


function buildCreate2Address(creatorAddress, saltHex, byteCode) {
  return `0x${web3.utils
    .soliditySha3(
      { t: 'bytes1', v: '0xff' },
      { t: 'address', v: creatorAddress },
      { t: 'bytes32', v: saltHex },
      {
        t: 'bytes32',
        v: web3.utils.soliditySha3({ t: 'bytes', v: byteCode })
      }
    )
    .slice(-40)}`.toLowerCase()
}

describe("PineCore", function () {

  const zeroAddress = '0x0000000000000000000000000000000000000000'

  let owner
  let user
  let fromOwner

  const creationParams = {
    ...fromOwner,
    gas: 6e6,
    gasPrice: 21e9
  }

  const fakeKey = web3.utils.sha3('0x01')
  const anotherFakeKey = web3.utils.sha3('0x02')
  const ONE_ETH = new BN(1)
  const CRATIONCODE_VAULT =
    '6012600081600A8239F360008060448082803781806038355AF132FF'

  // Contracts
  let token1
  let vaultFactory
  let pineCore

  beforeEach(async function () {

    const accounts = await web3.eth.getAccounts()

    owner = accounts[1]
    user = accounts[2]
    fromOwner = { from: owner }

    // Create tokens
    token1 = await ERC20.new(creationParams)
    await token1.setBalance(new BN(1000000000), owner)

    // Deploy exchange
    pineCore = await PineCore.new(creationParams)

    // Deploy vault
    vaultFactory = await VaultFactory.new(creationParams)
  })

  describe('Constructor', function () {
    it('should be depoyed', async () => {
      const contract = await PineCore.new()

      expect(contract).to.not.be.equal(zeroAddress)
    })
  })

  describe('Cancel ETH Order', function () {
    it('should cancel an ETH order', async () => {
      const secret = web3.utils.randomHex(32)
      const witness = toAddress(secret)

      const data = web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'uint256'],
        [
          token1.address,               // Buy TOKEN 1
          new BN(300),                  // Get at least 300 Tokens
          new BN(10)                    // Pay 10 WEI to sender
        ]
      )

      // Create order
      const encodedOrder = await pineCore.encodeEthOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // ETH Address
        user,                             // Owner of the order
        witness,                          // Witness public address
        data,                             // data
        secret                            // Witness secret
      )

      // Take balance snapshots
      const exEtherSnap = await etherSnap(pineCore.address, 'Uniswap EX ETH')
      const userEtherSnap = await etherSnap(user, 'User ETH')
      const userTokenSnap = await balanceSnap(token1, user, 'User token1')
      const uniswapTokenSnap = await balanceSnap(
        token1,
        pineCore.address,
        'Uniswap Ex Token1'
      )

      const value = new BN(10000)
      const depositTx = await pineCore.depositEth(
        encodedOrder,
        {
          value,
          gasPrice: 0,
          from: user
        }
      )

      // Validate balances
      await exEtherSnap.requireIncrease(value)
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireDecrease(value)
      await userTokenSnap.requireConstant()

      // Cancel order
      const cancelTx = await pineCore.cancelOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // Sell ETH
        user,                             // Owner of the order
        witness,                      // witness
        data,                         // data
        {
          gasPrice: 0,
          from: user
        }
      )

      expect(cancelTx.logs[0].event).to.be.equal('OrderCancelled')
      expect(cancelTx.logs[0].args._key).to.be.equal(depositTx.logs[0].args._key)
      expect(cancelTx.logs[0].args._inputToken).to.be.equal(ethAddress)
      expect(cancelTx.logs[0].args._owner).to.be.equal(user)
      expect(cancelTx.logs[0].args._witness).to.be.equal(witness)
      expect(cancelTx.logs[0].args._data).to.be.equal(data)
      expect(cancelTx.logs[0].args._amount).to.be.eq.BN(value)

      // Validate balances
      await exEtherSnap.requireDecrease(value)
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireIncrease(value)
      await userTokenSnap.requireConstant()
    })

    it('should cancel token order', async () => {
      const secret = web3.utils.randomHex(32)
      const witness = toAddress(secret)

      const data = web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'uint256'],
        [
          ethAddress,               // Buy ETH
          new BN(50),               // Get at least 50 ETH Wei
          new BN(15)                // Pay 15 WEI to sender
        ]
      )

      const amount = new BN(10000)
      // Encode order transfer
      const orderTx = await pineCore.encodeTokenOrder(
        vaultFactory.address,     // Limit orders module
        token1.address,               // Sell token 1
        user,                         // Owner of the order
        witness,                      // Witness address
        data,                         // data
        secret,                       // Witness secret
        amount                    // Tokens to sell
      )

      const vaultAddress = await pineCore.vaultOfOrder(
        vaultFactory.address,     // Limit orders module
        token1.address,               // Sell token 1
        user,                         // Owner of the order
        witness,                      // Witness address
        data
      )

      const key = web3.utils.sha3(web3.eth.abi.encodeParameters(
        ['address', 'address', 'address', 'address', 'bytes'],
        [
          vaultFactory.address,
          token1.address,
          user,
          witness,
          data
        ]
      ))


      await token1.setBalance(amount, user)

      // Take balance snapshots
      const vaultETHSnap = await etherSnap(vaultAddress, 'Token vault ETH')
      const vaultTokenSnap = await balanceSnap(token1, vaultAddress, 'Token vault token1')
      const exEtherSnap = await etherSnap(pineCore.address, 'Uniswap EX ETH')
      const userEtherSnap = await etherSnap(user, 'User ETH')
      const userTokenSnap = await balanceSnap(token1, user, 'User token1')
      const uniswapTokenSnap = await balanceSnap(
        token1,
        pineCore.address,
        'Uniswap Ex Token1'
      )

      // Send tokens tx
      await web3.eth.sendTransaction({
        from: user,
        to: token1.address,
        data: orderTx,
        gasPrice: 0
      })


      // Validate balances
      await vaultETHSnap.requireConstant()
      await vaultTokenSnap.requireIncrease(amount)
      await exEtherSnap.requireConstant()
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireConstant()
      await userTokenSnap.requireDecrease(amount)

      // Cancel order
      const cancelTx = await pineCore.cancelOrder(
        vaultFactory.address,     // Limit orders module
        token1.address,               // Sell token 1
        user,                         // Owner of the order
        witness,                      // witness
        data,                         // data
        {
          from: user,
          gasPrice: 0
        }
      )

      expect(cancelTx.logs[0].event).to.be.equal('OrderCancelled')
      expect(cancelTx.logs[0].args._key).to.be.equal(key)
      expect(cancelTx.logs[0].args._inputToken).to.be.equal(token1.address)
      expect(cancelTx.logs[0].args._owner).to.be.equal(user)
      expect(cancelTx.logs[0].args._witness).to.be.equal(witness)
      expect(cancelTx.logs[0].args._data).to.be.equal(data)
      expect(cancelTx.logs[0].args._amount).to.be.eq.BN(amount)

      // Validate balances
      await vaultETHSnap.requireConstant()
      await vaultTokenSnap.requireDecrease(amount)
      await exEtherSnap.requireConstant()
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireConstant()
      await userTokenSnap.requireIncrease(amount)
    })

    it('should keep balance if the order was cancelled twice', async () => {
      const secret = web3.utils.randomHex(32)
      const witness = toAddress(secret)

      const data = web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'uint256'],
        [
          token1.address,               // Buy TOKEN 1
          new BN(300),                  // Get at least 300 Tokens
          new BN(10)                    // Pay 10 WEI to sender
        ]
      )

      // Create order
      const encodedOrder = await pineCore.encodeEthOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // ETH Address
        user,                             // Owner of the order
        witness,                          // Witness public address
        data,                             // data
        secret                            // Witness secret
      )

      // Take balance snapshots
      const exEtherSnap = await etherSnap(pineCore.address, 'Uniswap EX ETH')
      const userEtherSnap = await etherSnap(user, 'User ETH')
      const userTokenSnap = await balanceSnap(token1, user, 'User token1')
      const uniswapTokenSnap = await balanceSnap(
        token1,
        pineCore.address,
        'Uniswap Ex Token1'
      )

      const value = new BN(10000)
      const depositTx = await pineCore.depositEth(
        encodedOrder,
        {
          value,
          gasPrice: 0,
          from: user
        }
      )

      // Validate balances
      await exEtherSnap.requireIncrease(value)
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireDecrease(value)
      await userTokenSnap.requireConstant()

      // Cancel order
      const cancelTx = await pineCore.cancelOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // Sell ETH
        user,                             // Owner of the order
        witness,                      // witness
        data,                         // data
        {
          gasPrice: 0,
          from: user
        }
      )

      expect(cancelTx.logs[0].event).to.be.equal('OrderCancelled')
      expect(cancelTx.logs[0].args._key).to.be.equal(depositTx.logs[0].args._key)
      expect(cancelTx.logs[0].args._inputToken).to.be.equal(ethAddress)
      expect(cancelTx.logs[0].args._owner).to.be.equal(user)
      expect(cancelTx.logs[0].args._witness).to.be.equal(witness)
      expect(cancelTx.logs[0].args._data).to.be.equal(data)
      expect(cancelTx.logs[0].args._amount).to.be.eq.BN(value)

      // Validate balances
      await exEtherSnap.requireDecrease(value)
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireIncrease(value)
      await userTokenSnap.requireConstant()

      await pineCore.cancelOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // Sell ETH
        user,                             // Owner of the order
        witness,                      // witness
        data,                         // data
        {
          gasPrice: 0,
          from: user
        }
      )

      // Validate balances
      await exEtherSnap.requireConstant()
      await uniswapTokenSnap.requireConstant()
      await userEtherSnap.requireConstant()
      await userTokenSnap.requireConstant()

    })

    it('reverts when cancel by hacker', async () => {
      const secret = web3.utils.randomHex(32)
      const witness = toAddress(secret)

      const data = web3.eth.abi.encodeParameters(
        ['address', 'uint256', 'uint256'],
        [
          token1.address,               // Buy TOKEN 1
          new BN(300),                  // Get at least 300 Tokens
          new BN(10)                    // Pay 10 WEI to sender
        ]
      )

      // Create order
      const encodedOrder = await pineCore.encodeEthOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // ETH Address
        user,                             // Owner of the order
        witness,                          // Witness public address
        data,                             // data
        secret                            // Witness secret
      )

      const value = new BN(10000)
      await pineCore.depositEth(
        encodedOrder,
        {
          value,
          from: user
        }
      )

      // Cancel order
      await assertRevert(pineCore.cancelOrder(
        vaultFactory.address,         // Limit orders module
        ethAddress,                       // Sell ETH
        user,                             // Owner of the order
        witness,                      // witness
        data,                         // data
        fromOwner
      ), 'PineCore#cancelOrder: INVALID_OWNER')
    })
  })

  describe('Get vault', function () {
    it('should return correct vault', async function () {
      const address = (await vaultFactory.getVault(fakeKey)).toLowerCase()
      const expectedAddress = buildCreate2Address(
        vaultFactory.address,
        fakeKey,
        CRATIONCODE_VAULT
      )
      expect(address).to.not.be.equal(zeroAddress)
      expect(address).to.be.equal(expectedAddress)
    })

    it('should return same vault for the same key', async function () {
      const address = await vaultFactory.getVault(fakeKey)
      const expectedAddress = await vaultFactory.getVault(fakeKey)
      expect(address).to.be.equal(expectedAddress)
    })

    it('should return a different vault for a different key', async function () {
      const address = await vaultFactory.getVault(fakeKey)
      const expectedAddress = await vaultFactory.getVault(anotherFakeKey)
      expect(address).to.not.be.equal(zeroAddress)
      expect(expectedAddress).to.not.be.equal(zeroAddress)
      expect(address).to.not.be.equal(expectedAddress)
    })
  })

  describe('Create vault', function () {
    it('should return correct vault', async function () {
      const address = await vaultFactory.getVault(fakeKey)
      await token1.setBalance(ONE_ETH, address)
      await vaultFactory.executeVault(fakeKey, token1.address, user)
    })

    it('not revert if vault has no balance', async function () {
      await vaultFactory.executeVault(fakeKey, token1.address, user)
    })
  })
})