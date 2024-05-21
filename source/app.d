import vibe.vibe;
import std.typecons;
import errorstrings;
import std.stdio;
import std.algorithm;
import std.file;
import std.path;
import vibe.core.path;
@safe:


struct Model
{
    string endpoint;
    Authset authset;
    @optional
    {
        Json[string] defaults;
        Json[string] overrides;
    }
}

alias Models = Model[string];
alias Authset = string[string];

bool isNumericalJsonType(Json.Type jsontype)
{
    return ![Json.Type.bigInt, Json.Type.float_, Json.Type.int_].find(jsontype).empty;
}

void handleOpenAICompletion(Model model, HTTPServerRequest inputReq, HTTPServerResponse outputRes)
{
    requestHTTP(model.endpoint, (scope req) {
        foreach (key; model.authset.byKey)
        {
            req.headers[key] = model.authset[key];
        }
        req.method = HTTPMethod.POST;
        // Remove unused parameters for compatibility
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
        if (outJson["presence_penalty"].type.isNumericalJsonType
            && outJson["presence_penalty"].get!double == 0)
        {
            outJson.remove("presence_penalty");
        }
        if (outJson["frequency_penalty"].type.isNumericalJsonType
            && outJson["frequency_penalty"].get!double == 0)
        {
            outJson.remove("frequency_penalty");
        }
        if (outJson["best_of"].type == Json.Type.int_ && inputReq.json["best_of"].get!int
            == 1)
        {
            outJson.remove("best_of");
        }
        req.writeJsonBody(outJson);
    }, (scope res) {
        outputRes.statusCode = res.statusCode;
        outputRes.writeJsonBody(res.readJson);
    });
}

struct Conduit
{
    Models models;
    Authset[string] authsets;

    void completions(HTTPServerRequest req, HTTPServerResponse res)
    {
        enforceHTTP("model" in req.json, HTTPStatus.badRequest, "'model' parameter is required");
        string modelname = req.json["model"].to!string;
        enforceHTTP(modelname in models, HTTPStatus.badRequest, unauthorizedOrModelNotFound);
        Model model = models[modelname];
        handleOpenAICompletion(model, req, res);
    }
}

void addConduitRoutes(ref URLRouter router, ref Conduit conduit)
{
    router.post("/v1/completions", &conduit.completions);
    router.post("/v1/chat/completions", &conduit.completions);
}

void main()
{
    import std.process;

    Conduit conduit;
    alias loadConfig = (path) {
        if (!path.toString.endsWith(".json")) return;
        auto models = deserializeJson!Models(path.readFileUTF8);
        foreach (k, v; models)
        {
            conduit.models[k] = v;
        }
    };
    auto configDir = "~/.config/conduit/".expandTilde;
    auto watcher = watchDirectory(configDir);
    runTask(() nothrow {
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
        catch (Exception e) {}
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
