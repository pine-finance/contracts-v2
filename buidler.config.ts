import { BuidlerConfig } from "@nomiclabs/buidler/config"
import { usePlugin } from "@nomiclabs/buidler/config"

usePlugin('@nomiclabs/buidler-truffle5')
usePlugin('@nomiclabs/buidler-web3')

const config: BuidlerConfig = {
  solc: {
    version: '0.6.8',
    optimizer: {
      enabled: true,
      runs: 1000000
    }
  }
}

export default config