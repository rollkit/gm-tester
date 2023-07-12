apt update
apt install jq -y
curl https://get.ignite.com/cli@v0.26.1! | bash
git clone https://github.com/rollkit/cosmos-sdk.git
cd cosmos-sdk
echo "checking out $COSMOS_CHECKOUT"
COSMOS_CHECKOUT=$COSMOS_CHECKOUT git checkout $COSMOS_CHECKOUT
cd ..
ignite scaffold chain gm --address-prefix gm
cd gm
go mod edit -replace github.com/cosmos/cosmos-sdk=../cosmos-sdk
go mod edit -replace github.com/tendermint/tendermint=github.com/rollkit/cometbft@v0.0.0-20230524013049-75272ebaee38
go mod tidy
go mod download

VALIDATOR_NAME=validator1
CHAIN_ID=gm
KEY_NAME=gm-key
KEY_2_NAME=gm-key-2
CHAINFLAG="--chain-id ${CHAIN_ID}"
TOKEN_AMOUNT="10000000000000000000000000stake"
STAKING_AMOUNT="1000000000stake"

# create a random Namespace ID for your rollup to post blocks to
NAMESPACE_ID=$(openssl rand -hex 8)
echo $NAMESPACE_ID

# build the gm chain with Rollkit
ignite chain build
# reset any existing genesis/chain data
gmd tendermint unsafe-reset-all

# initialize the validator with the chain ID you set
gmd init $VALIDATOR_NAME --chain-id $CHAIN_ID

# add keys for key 1 and key 2 to keyring-backend test
echo y | gmd keys add $KEY_NAME --keyring-backend test
echo y | gmd keys add $KEY_2_NAME --keyring-backend test

# add these as genesis accounts
gmd add-genesis-account $KEY_NAME $TOKEN_AMOUNT --keyring-backend test
gmd add-genesis-account $KEY_2_NAME $TOKEN_AMOUNT --keyring-backend test

# set the staking amounts in the genesis transaction
gmd gentx $KEY_NAME $STAKING_AMOUNT --chain-id $CHAIN_ID --keyring-backend test

# collect genesis transactions
gmd collect-gentxs

# query the DA Layer start height, in this case we are querying
# our local devnet at port 26657, the RPC. The RPC endpoint is
# to allow users to interact with Celestia's nodes by querying
# the node's state and broadcasting transactions on the Celestia
# network. The default port is 26657.
DA_BLOCK_HEIGHT=$(curl http://celestia:26657/block | jq -r '.result.block.header.height')
echo $DA_BLOCK_HEIGHT

# start the chain
echo "Starting rollup in background!"
gmd start --rollkit.aggregator true --rollkit.da_layer celestia --rollkit.da_config='{"base_url":"http://celestia:26659","timeout":60000000000,"fee":6000,"gas_limit":6000000}' --rollkit.namespace_id $NAMESPACE_ID --rollkit.da_start_height $DA_BLOCK_HEIGHT &

URL=localhost:26657/block\?height=3
EXPECTED_RESULT='{"jsonrpc":"2.0","error":{"code":-32603,"message":"","data":"failed to load hash from index: failed to load block hash for height: datastore: key not found"},"id":-1}'

# Define the maximum number of retries
MAX_RETRIES=50

# Define the delay between retries in seconds
RETRY_DELAY=5

# Counter for the number of retries
RETRY_COUNT=0

# Loop until the result is not equal to the expected string or maximum retries are reached
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
  # Execute the curl command and capture the result
  RESULT=$(curl -s "$URL")

  # Compare the result with the expected string or null string
  if [[ "$RESULT" != "$EXPECTED_RESULT" && -n "$RESULT" ]]; then
    echo "Success! The result is now different from the expected string or null string."
    break
  fi
  echo "EXPECTED " $EXPECTED_RESULT
  echo "GOT " $RESULT

  # Increment the retry count
  ((RETRY_COUNT++))

  # Display a retry message
  echo "Retrying... (Attempt $RETRY_COUNT)"

  # Sleep for the specified delay before the next retry
  sleep $RETRY_DELAY
done

# Check if maximum retries are reached without success
if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
  echo "Maximum retries reached. Unable to obtain a different result."
fi


## uncomment the next command if you are using lazy aggregation
## gmd start --rollkit.aggregator true --rollkit.da_layer celestia --rollkit.da_config='{"base_url":"http://localhost:26659","timeout":60000000000,"fee":6000,"gas_limit":6000000}' --rollkit.namespace_id $NAMESPACE_ID --rollkit.da_start_height $DA_BLOCK_HEIGHT --rollkit.lazy_aggregator true
