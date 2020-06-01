import { web3 } from '@nomiclabs/buidler'
const eutils = require('ethereumjs-util')

export function toAddress(pk) {
  return eutils.toChecksumAddress(eutils.bufferToHex(eutils.privateToAddress(eutils.toBuffer(pk))))
}

export function sign(address, priv) {
  const hash = web3.utils.soliditySha3(
    { t: 'address', v: address }
  )
  const sig = eutils.ecsign(
    eutils.toBuffer(hash),
    eutils.toBuffer(priv)
  )

  return eutils.bufferToHex(Buffer.concat([sig.r, sig.s, eutils.toBuffer(sig.v)]))
}