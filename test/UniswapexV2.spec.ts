import { web3, artifacts } from '@nomiclabs/buidler'

const BN = web3.utils.BN
const expect = require('chai').use(require('bn-chai')(BN)).expect

const ERC20 = artifacts.require('FakeERC20')
const UniswapexV2 = artifacts.require('UniswapexV2')
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

describe("UniswapexV2", function () {

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
  let uniswapEx

  beforeEach(async function () {

    const accounts = await web3.eth.getAccounts()

    owner = accounts[1]
    user = accounts[2]
    fromOwner = { from: owner }

    // Create tokens
    token1 = await ERC20.new(creationParams)
    await token1.setBalance(new BN(1000000000), owner)

    // Deploy exchange
    uniswapEx = await UniswapexV2.new(creationParams)

    // Deploy vault
    vaultFactory = await VaultFactory.new(creationParams)
  })

  describe('Constructor', function () {
    it('should be depoyed', async function () {
      const contract = await UniswapexV2.new()

      expect(contract).to.not.be.equal(zeroAddress)
    })
  })

  describe('Cancel ETH Order', function () {
    it('should cancel an ETH order')
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