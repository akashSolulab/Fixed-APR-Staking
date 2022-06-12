
## Fixed APR Staking Contract

> Staking Contract for Stable Coin Staking. User can stake stable coins into the pool and generate rewards in form of ERC20 tokens.


**Rules:**
---
 1. The rewards will be based on the `APR` mechanism
 2. Rewards are pegged with staking duration:
	 a. 1 month - 5% `APR`
	 b. 6 months - 10% `APR`
	 c. 12 months - 15% `APR`
	 d. After 1 year - stable at 15% `APR`
 3. Additional perks pegged with staked amount in the pool:
	a. $100 - Extra 2% `APR`
	b. $500 - Extra 5% `APR`
	c. $1000 - Extra 10% `APR`

**Technical Specification:**
---

1. Solidity - Smartcontract
2. Hardhat - Deployment environment, UUPS Proxy, Testing
3. Openzeppelin - Smartcontract libraries
4. Ether.js - Web3 library
5. Chai.js - Test-cases
6. Alchemy - Node as a service

**Steps**
---
1. Clone this repository
	```
	$ git clone https://github.com/akashSolulab/Fixed-APR-Staking.git
	``` 
2. Move to the folder directory
	```
	$ cd Fixed-APR-Staking
	```
3. Install dependencies
	```
	$  npm install
	```
4. Test smartcontract (on rinkeby testnet)
	```
	$ npx hardhat test --network rinkeby
	```
5. Deploy smartcontract (on rinkeby testnet)
	```
	$ npx hardhat run scripts/deployProxyContract.js --network rinkeby
	```