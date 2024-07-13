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

## Download
Go to [actions](https://github.com/ampdot-io/conduit/actions), click on the latest commit with a green icon on the `main` branch, scroll down to "artifacts" and download the appropriate binary for your operating system.

On Linux and macOS, rename the resultant file to `conduit`

## Usage
```
./conduit
```

Create a config file at `~/config/conduit/models.json`.

### Example configurations
Mixtral 8x22B via together.ai:
```
{
    "mistralai/Mixtral-8x22B-v0.1": {
        "endpoint": "https://api.together.xyz/v1/completions",
        "overrides": {
            "model": "mistralai/Mixtral-8x22B"
        },
        "authset": {
            "Authorization": "Bearer YOUR_TOGETHER_API_KEY_HERE"
        }
    }
}
```

Claude steering via `/v1/completions`:
```
{
    "claude-3-sonnet-20240229-steering-preview": {
        "authset": {
            "anthropic-beta": "steering-2024-06-04",
            "anthropic-version": "2023-06-01",
            "x-api-key": "YOUR_ANTHROPIC_API_KEY_HERE"
        },
        "type": "anthropicMessages",
        "endpoint": "https://api.anthropic.com/v1/messages",
        "systemPrompt": "The assistant is in CLI simulation mode, and responds to the user's CLI commands only with the output of the command.",
        "initialMessages": [{
            "role": "user",
            "content": "<cmd>cat untitled.txt</cmd>"
        }]
    }
}
```
Set the default temperature on a model:
```
{
    "gpt-3.5-turbo": {
        "endpoint": "https://api.openai.com/v1/completions",
        "authset": {
            "Authorization": "Bearer YOUR_OPENAI_KEY_HERE"
        },
        "defaults": {
            "temperature": 0
        }
    }
}
```

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
