
#!/bin/bash

set -e
pushd $(dirname $0)

mkdir -p tmp
nasm res/$1.asm -o tmp/$1 && zig build run -- tmp/$1 > tmp/$1_self.asm && nasm tmp/$1_self.asm && diff tmp/$1 tmp/$1_self

popd
