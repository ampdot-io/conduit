static import std.json;
import std.algorithm;
import vibe.vibe;
import std.typecons;
import errorstrings;
import std.stdio;
import std.algorithm;
import std.file;
import std.path;
import vibe.core.path;
import std.net.curl;
import std.process; // env variables
import std.ascii;
import std.random;
import std.range;
import std.base64;
import std.string;
import std.array;
import std.regex;
import std.functional;

@safe:

enum APIType
{
    openai,
    anthropicMessages,
    ollama,
}

struct Model
{
    string endpoint;
    @optional @byName APIType type = APIType.openai;
    @optional
    {
        Authset authset;
        Json[string] defaults;
        Json[string] overrides;
        // Chat-model specific
        string systemPrompt;
        Json[] initialMessages;
        string promptRole = "assistant";
    }
}

alias Models = Model[string];
alias Authset = string[string];

bool isNumericalJsonType(Json.Type jsontype)
{
    return ![Json.Type.bigInt, Json.Type.float_, Json.Type.int_].find(jsontype).empty;
}

bool isAnthropicModel(string modelName)
{
    return modelName.startsWith("claude");
}

string detectFileType(const ubyte[] data)
{
    if (data.length < 4)
    {
        return "Unknown - not enough data";
    }
    if (data.startsWith(cast(ubyte[])[0xFF, 0xD8, 0xFF]))
    {
        return "image/jpeg";
    }
    else if (data.startsWith(cast(ubyte[])[0x89, 0x50, 0x4E, 0x47]))
    {
        return "image/png";
    }
    else if (data.startsWith(cast(ubyte[])[0x47, 0x49, 0x46, 0x38]))
    {
        return "image/gif";
    }
    else if (data.startsWith(cast(ubyte[])[0x52, 0x49, 0x46, 0x46])
            && data[8 .. 12].equal(cast(ubyte[])[0x57, 0x45, 0x42, 0x50]))
    {
        return "image/webp";
    }
    return "Unknown file type";
}

void handleOpenAICompletion(Model model, HTTPServerRequest inputReq, HTTPServerResponse outputRes)
{
    requestHTTP(model.endpoint, (scope req) {
        foreach (key; model.authset.byKey)
        {
            req.headers[key] = model.authset[key];
        }
        req.method = HTTPMethod.POST;
        auto outJson = inputReq.json;
        foreach (key, value; model.defaults)
        {
            if (key !in outJson)
            {
                outJson[key] = value;
            }
        }
        foreach (key, value; model.overrides)
        {
            outJson[key] = value;
        }
        // Remove unused parameters for compatibility
        if (outJson["presence_penalty"].type.isNumericalJsonType
            && outJson["presence_penalty"].to!double == 0)
        {
            outJson.remove("presence_penalty");
        }
        if (outJson["frequency_penalty"].type.isNumericalJsonType
            && outJson["frequency_penalty"].to!double == 0)
        {
            outJson.remove("frequency_penalty");
        }
        if (outJson["best_of"].type == Json.Type.int_ && inputReq.json["best_of"].get!int == 1)
        {
            outJson.remove("best_of");
        }

        final switch (model.type)
        {
        case APIType.openai:
            break;
        case APIType.anthropicMessages:
            // TODO: Set a default prompt if "prompt" parameter is unspecified
            outJson["system"] = model.systemPrompt;
            Json[] messages;
            auto text = (outJson["prompt"].to!string).splitter(
                regex(`<\|(?:begin|end)_of_img_url\|>`));
            foreach (i, section; text.enumerate)
            {
                if ((i % 2) == 0)
                {
                    if (!section.isWhite) {
                        messages ~= [
                            Json([
                                "role": Json(model.promptRole),
                                "content": Json(section)
                            ])
                        ];
                    }
                }
                else
                {
                    ubyte[] range;
                    ubyte[] downloadURL(string url)
                    {
                        return std.net.curl.get!(AutoProtocol, ubyte)(url);

                    }

                    try
                    {
                        range = memoize!downloadURL(section);
                    }
                    catch (CurlException e)
                    {
                        // TODO: Handle this error
                        return;
                    }
                    string asBase64 = Base64.encode(range);
                    messages ~= [
                        Json([
                            "role": "user",
                            "content": Json([Json([
                                "type": Json("image"),
                                "source": Json([
                                    "type": Json("base64"),
                                    "media_type": Json(detectFileType(range)),
                                    "data": Json(asBase64)
                                ])
                            ])])
                        ])
                    ];
                }
            }
            outJson["messages"] = model.initialMessages ~ messages;
            if (outJson["stop"].type != Json.Type.undefined)
            {
                outJson["stop_sequences"] = outJson["stop"];
                outJson.remove("stop");
            }
            outJson.remove("logit_bias");
            outJson.remove("prompt");
            if (outJson["max_tokens"].type() == Json.Type.undefined)
            {
                outJson["max_tokens"] = 16;
            }
            break;
        case APIType.ollama:
            auto prevOutJson = outJson;
            outJson = Json.emptyObject;
            outJson["model"] = prevOutJson["model"];
            outJson["prompt"] = prevOutJson["prompt"];
            prevOutJson.remove("model");
            prevOutJson.remove("prompt");
            outJson["stream"] = false.Json;
            outJson["raw"] = true.Json;
            outJson["options"] = prevOutJson;
            if (outJson["options"]["max_tokens"].type != Json.Type.undefined)
            {
                outJson["options"]["num_predict"] = outJson["options"]["max_tokens"];
                outJson["options"].remove("max_tokens");
            }

            break;
        }
        req.writeJsonBody(outJson);
    }, (scope res) {
        outputRes.statusCode = res.statusCode;
        void passthroughError(string errorKind)
        {
            auto bodyContents = res.bodyReader.readAllUTF8;
            writeln(errorKind, " ", "error: ", bodyContents);
            outputRes.writeBody(bodyContents);
            return;
        }

        if (res.statusCode > 299 || res.statusCode < 200)
        {
            passthroughError("Non-OK status code");
            return;
        }
        Json inputJson;
        try
        {
            inputJson = res.readJson;
        }
        catch (std.json.JSONException)
        {
            passthroughError("Failed to parse JSON");
            return;
        }
        scope (failure)
            writeln(inputJson);
        Json outJson = inputJson;
        if (outJson["created"].type() == Json.Type.undefined)
        {
            outJson["created"] = Clock.currTime.toUnixTime!long;
        }
        final switch (model.type)
        {
        case APIType.openai:
            break;
        case APIType.anthropicMessages:
            Json text;
            if (outJson["content"].length == 0)
            {
                text = "";
            }
            else if (outJson["content"].length == 1)
            {
                text = outJson["content"][0]["text"];
                if (outJson["content"].length > 1)
                {
                    writeln(outJson["content"]);
                }
            }
            string oaiStopReason;
            final switch (outJson["stop_reason"].get!string)
            {
            case "end_turn":
                oaiStopReason = "stop";
                break;
            case "max_tokens":
                oaiStopReason = "length";
                break;
            case "stop_sequence":
                oaiStopReason = "stop";
                break;
            case "tool_use":
                oaiStopReason = "stop";
                break;
            }
            outJson["choices"] = [
                Json([
                    "text": text,
                    "index": 0.Json,
                    "logprobs": null.Json,
                    "stop_reason": oaiStopReason.Json
                ])
            ];
            outJson["usage"] = Json([
                "prompt_tokens": outJson["usage"]["input_tokens"],
                "completion_tokens": outJson["usage"]["output_tokens"],
                "total_tokens": Json(
                    outJson["usage"]["input_tokens"].get!long
                    + outJson["usage"]["output_tokens"].get!long)
            ]);
            break;
        case APIType.ollama:
            outJson["choices"] = [
                Json([
                    "text": outJson["response"],
                    "index": 0.Json,
                    "logprobs": null.Json,
                    "stop_reason": "unknown".Json,

                

            ])];
            break;
        }
        if (outJson["id"].type == Json.Type.undefined)
        {
            outJson["id"] = "duit-" ~ generateRandomString(30);
        }
        outputRes.writeJsonBody(outJson);
    });
}

struct Conduit
{
    Models models;
    Authset[string] authsets;

    void completions(HTTPServerRequest req, HTTPServerResponse res)
    {
        enforceHTTP("model" in req.json, HTTPStatus.badRequest, "'model' parameter is required");
        string modelName = req.json["model"].to!string;
        Model model;
        if (modelName in models)
        {
            model = models[modelName];
        }
        else if (modelName.startsWith("claude-"))
        {
            model.systemPrompt = "The assistant is in CLI simulation mode, and responds to the user's CLI commands only with the output of the command.";
            model.initialMessages = [
                Json([
                    "role": Json("user"),
                    "content": Json("<cmd>cat <untitled.txt</cmd>")
                ])
            ];
            model.endpoint = "https://api.anthropic.com/v1/messages";
            model.type = APIType.anthropicMessages;
            model.authset = [
                "X-Api-Key": environment.get("ANTHROPIC_API_KEY"),
                "Anthropic-Version": "2023-06-01"
            ];
        }
        else
        {
            enforceHTTP(false, HTTPStatus.badRequest, unauthorizedOrModelNotFound);
        }
        handleOpenAICompletion(model, req, res);
    }

    void listModels(HTTPServerRequest req, HTTPServerResponse res)
    {
        Json jsonModels = Json.emptyObject;
        jsonModels["object"] = Json("list");
        jsonModels["data"] = Json.emptyArray;
        foreach (modelName, model; models)
        {
            jsonModels["data"] ~= Json([
                "id": Json(modelName),
                "object": Json("model"),
                "created": Json(0),
                "owned_by": Json("conduit")
            ]);
        }
        res.writeJsonBody(jsonModels);
    }
}

void addConduitRoutes(ref URLRouter router, ref Conduit conduit)
{
    router.post("/v1/completions", &conduit.completions);
    router.post("/v1/chat/completions", &conduit.completions);
    router.get("/v1/models", &conduit.listModels);
}

void main()
{
    import std.process;

    Conduit conduit;
    // XXX: Removing models does not work
    alias loadConfig = (path) {
        if (!path.toString.endsWith(".json"))
            return;
        auto models = deserializeJson!Models(path.readFileUTF8);
        foreach (k, v; models)
        {
            conduit.models[k] = v;
        }
    };
    auto configDir = "~/.config/conduit/".expandTilde;
    auto watcher = watchDirectory(configDir);
    runTask(() nothrow{
        try
        {
            while (true)
            {
                DirectoryChange[] changes;
                watcher.readChanges(changes, Duration.max);
                foreach (change; changes)
                {
                    if (change.type != DirectoryChangeType.removed)
                    {
                        writeln("Loading config!");
                        loadConfig(change.path);
                    }
                }
            }
        }
        catch (Exception e)
        {
        }
    });
    listDirectory(configDir, (fileInfo) {
        loadConfig(fileInfo.directory ~ fileInfo.name);
        return true;
    });
    auto router = new URLRouter;
    router.addConduitRoutes(conduit);
    auto settings = new HTTPServerSettings;
    settings.port = 6010;
    listenHTTP(settings, router);
    runApplication();
}

string generateRandomString(size_t length)
{
    string result;
    foreach (_; 0 .. length)
    {
        char randomChar = letters[uniform(0, $)];
        result ~= randomChar;
    }
    return result;
}
