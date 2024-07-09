# conduit
conduit is a universal interoperability/compatibility layer for accessing language models and ems built atop them

## Roadmap
- [x] OpenAI-like support
 - [x] /v1/completions
 - [x] /v1/chat/completions
- [ ] Anthropic support
- [ ] Gemini support
- [ ] Precompiled statically-linked binaries via GitHub Actions
- [ ] Interface for adding and removing models
- [x] Hot-reloading of models
- [ ] WASM/JS compatibility library

## Developing

Install Dlang:

```
curl https://dlang.org/install.sh | bash -s
```

Use LDC on macOS:
```
curl https://dlang.org/install.sh | bash -s ldc
source ~/dlang/ldc-1.37.0/activate
```

Build:
```
dub build
```
