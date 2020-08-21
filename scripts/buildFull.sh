#! /bin/bash

UNISWAPEX_V2=UniswapexV2.sol
LIMIT_ORDERS_MODULE=LimitOrder.sol
UNISWAP_V1_HANDLER=UniswapV1Handler.sol
UNISWAP_V2_HANDLER=UniswapV2Handler.sol

OUTPUT=full

npx truffle-flattener contracts/$UNISWAPEX_V2 > $OUTPUT/$UNISWAPEX_V2
npx truffle-flattener contracts/modules/$LIMIT_ORDERS_MODULE > $OUTPUT/$LIMIT_ORDERS_MODULE
npx truffle-flattener contracts/handlers/$UNISWAP_V1_HANDLER > $OUTPUT/$UNISWAP_V1_HANDLER
npx truffle-flattener contracts/handlers/$UNISWAP_V2_HANDLER > $OUTPUT/$UNISWAP_V2_HANDLER
