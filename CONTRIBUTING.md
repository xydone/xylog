# Contributor guidelines

## Vision

The vision behind xylog is the following:

- xylog is meant to be a **lightweight, opinionated** media server.

Performance and memory usage are a priority and it is not supposed to support every single format and standard in the world.
Focusing on performance does not mean offloading expensive operations to the client.

- xylog is a **comics,manga** media server.

It is primarily designed for comics/mangas/any media that can be fragmented into a `1 Book <- many chapters`, with the chapters being individual files. We should try our best to maintain support for single file traditional books.

- xylog is designed with a self-hosted, cut out from the internet environment in mind.

The core features should work entirely on LAN. Internet-bound features are acceptable, as long as they are not critical.
An example for a non-critical internet-bound feature is a metadata collector.

- The clients that are targeted may have questionable performance characteristics.

xylog should be able to be used on any client hardware and it is designed with eReaders in mind.
Expensive operations, wherever possible, should be done on the server side.

## Proposals

If you have any feature requests and proposals that fit the vision of the future of xylog, open an issue with the label `Proposal`.

## Bugs

If you encounter any bugs and issues, open an issue with the label `Bug`. Include a reproducible example if possible.

## Pull requests

If the pull request introduces a new feature, please make sure to first file a `proposal` issue before beginning work on the pull request, as it is possible the feature does not get accepted and your time is wasted.

If the pull request is a bug-fix, there is no need for an issue.

Please follow the style guide when sending pull requests.

## Style guide

- Use `zig fmt`.

- File and library `@import`s should be at the bottom of the file.
[You can check out the following discussion on why imports at the bottom are neat.](https://ziggit.dev/t/rationale-behind-import-at-the-end-of-file/9116)

- Function names are camelCase. Variables are snake_case. Types are PascalCase.

- Code should document itself, but for public functions/variables/types/etc, include a [doc comment](https://ziglang.org/documentation/master/#Doc-Comments) when necessary (such as for when the function returns something that needs to be freed).
