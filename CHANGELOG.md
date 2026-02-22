# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2026-02-22

### Added
- **feat**: Add subpath exports for types, streaming, wasm, and dictionary files
- **feat**: Restore `DICTIONARY_PROFILES` and profile-based `createTokenizer()` API

### Changed
- **refactor**: Optimize npm package size (66MB → 12MB) by excluding uncompressed dictionaries
- **refactor**: Exclude `.d.ts` files from vite demo build

### Fixed
- **fix**: Build `micado-streaming` before `npm/micado-wasm` in CI workflows

## [0.3.0] - 2026-02-22

### Changed
- **refactor**: Extract shared streaming package (`@trkbt10/micado-streaming`) and simplify API

### Chores
- Consolidate `.gitignore` to root

## [0.2.0] - 2025-xx-xx

### Added
- **feat**: Enable `-d/--dicdir` option for custom dictionary loading
- **feat**: Add MeCab dictionary CSV source converter
- **feat**: Add MeCab-compatible CLI for npm package
- **feat**: Add constrained parsing and n-best APIs with mecab-like CLI
- **feat**: Add npm README and version sync from moon.mod.json

### Fixed
- **fix**: Disable source maps to prevent browser MIME type errors
- **fix**: Add repository field to package.json for provenance
- **fix**: Rename npm package to `@trkbt10/micado`

### Changed
- **refactor**: Split tokenize CLI arg parser and add wb tests
- **refactor**: Split library/cli boundaries and add release-asset workflow
- Migrate npm/micado-wasm and workers/micado-edge to TypeScript

## [0.1.0] - 2025-xx-xx

### Added
- Initial release of micado Japanese morphological analyzer
- MoonBit-based tokenizer with WASM runtime
- Double-array trie implementation for efficient dictionary lookup
- Viterbi algorithm for optimal path selection
- IPA dictionary and NEologd dictionary support
- Basic CLI for tokenization
