usePlugin('@nomiclabs/buidler-truffle5')
usePlugin('@nomiclabs/buidler-web3')

module.exports = {
  solc: {
    version: '0.6.8',
    optimizer: {
      enabled: true,
      runs: 1000000,
    },
  },
}
