
#!/bin/bash

set -e
pushd $(dirname $0)

./test.sh listing_37
./test.sh listing_38
./test.sh listing_39
./test.sh listing_40
./test.sh listing_41
./test.sh listing_42

popd
