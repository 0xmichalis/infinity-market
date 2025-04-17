# Infinity Marketplace

[![Coverage](https://coveralls.io/repos/github/0xmichalis/infinity-market/badge.svg?branch=main)](https://coveralls.io/github/0xmichalis/infinity-market?branch=main)[![Build](https://github.com/0xmichalis/infinity-market/actions/workflows/build.yml/badge.svg)](https://github.com/0xmichalis/infinity-market/actions/workflows/build.yml) [![Tests](https://github.com/0xmichalis/infinity-market/actions/workflows/test.yml/badge.svg)](https://github.com/0xmichalis/infinity-market/actions/workflows/test.yml) [![Lint](https://github.com/0xmichalis/infinity-market/actions/workflows/lint.yml/badge.svg)](https://github.com/0xmichalis/infinity-market/actions/workflows/lint.yml) [![Static analysis](https://github.com/0xmichalis/infinity-market/actions/workflows/analyze.yml/badge.svg)](https://github.com/0xmichalis/infinity-market/actions/workflows/analyze.yml)

`InfinityMarketplace` is a marketplace contract that can be used to trade NFTs whose approval mechanism is broken for whatever reason but the tokens are still transferrable. One example of such an NFT is [`Infinity`](https://etherscan.io/token/0x0082578eedfd01ec97c36165469d012d6dc257cc), hence the marketplace contract name, though the marketplace has been designed to support any ERC721 or ERC1155 token.

## Current limitations

* Collection offers are not supported

**The code in this repository is not audited so use at your own risk!**

## Install

```sh
git clone https://github.com/0xmichalis/infinity-market.git
cd infinity-market
forge install
```

## Build

```sh
forge build
```

## Test

```sh
forge test
```

## Update Gas Snapshot

```sh
forge snapshot
```
