import { web3, artifacts } from '@nomiclabs/buidler'

import { balanceSnap, etherSnap } from '../helpers/balanceSnap'
import { ethAddress } from '../helpers/account'

const BN = web3.utils.BN
const expect = require('chai').use(require('bn-chai')(BN)).expect

const ERC20 = artifacts.require('FakeERC20')
const Splitter = artifacts.require('Splitter')
const WETH = artifacts.require('WETH9')

describe('Splitter', function () {
  let token: any
  let weth: any
  let splitter: any

  let addra: string
  let addrb: string
  let owner: string

  beforeEach(async function () {
    const accounts = await web3.eth.getAccounts()

    addra = accounts[9]
    addrb = accounts[8]
    owner = accounts[7]

    token = await ERC20.new()
    weth = await WETH.new()

    splitter = await Splitter.new(weth.address, addra, addrb, owner)
  })

  it('Should split single ERC20', async () => {
    await token.setBalance(20, splitter.address)

    const snapa = await balanceSnap(token, addra, "address a")
    const snapb = await balanceSnap(token, addrb, "address b")
    const snaps = await balanceSnap(token, splitter.address, "splitter")

    await splitter.withdraw([token.address], [20])

    await snapa.requireIncrease(10)
    await snapb.requireIncrease(10)
    await snaps.requireDecrease(20)
  })

  it('Should split ETH', async () => {
    await web3.eth.sendTransaction({
      from: owner,
      to: splitter.address,
      value: 31
    })

    const snapa = await balanceSnap(weth, addra, "address a")
    const snapb = await balanceSnap(weth, addrb, "address b")
    const snapsw = await balanceSnap(weth, splitter.address, "splitter")
    const snapse = await etherSnap(splitter.address, "splitter")

    await splitter.withdraw([ethAddress], [31])

    await snapa.requireIncrease(15)
    await snapb.requireIncrease(15)
    await snapse.requireDecrease(31)
    await snapsw.requireIncrease(1)
  })

  it('Should split ETH and ERC20', async () => {
    await token.setBalance(30, splitter.address)
    await web3.eth.sendTransaction({
      from: owner,
      to: splitter.address,
      value: 50
    })

    const snapta = await balanceSnap(token, addra, "address a")
    const snaptb = await balanceSnap(token, addrb, "address b")
    const snapts = await balanceSnap(token, splitter.address, "splitter")

    const snapea = await balanceSnap(weth, addra, "address a")
    const snapeb = await balanceSnap(weth, addrb, "address b")
    const snapes = await etherSnap(splitter.address, "splitter")

    await splitter.withdraw([token.address, ethAddress], [30, 50])

    await snapta.requireIncrease(15)
    await snaptb.requireIncrease(15)
    await snapts.requireDecrease(30)

    await snapea.requireIncrease(25)
    await snapeb.requireIncrease(25)
    await snapes.requireDecrease(50)
  })
})
