import vibe.vibe;
import std.typecons;
import errorstrings;
import std.stdio;
import std.algorithm;

struct Model
{
    string endpoint;
    Authset authset;
    Nullable!string completions_handler;
    Nullable!string chatcompletions_handler;
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
        if (inputReq.json["presence_penalty"].type.isNumericalJsonType
            && inputReq.json["presence_penalty"].get!double == 0)
        {
            inputReq.json.remove("presence_penalty");
        }
        if (inputReq.json["frequency_penalty"].type.isNumericalJsonType
            && inputReq.json["frequency_penalty"].get!double == 0)
        {
            inputReq.json.remove("frequency_penalty");
        }
        if (inputReq.json["best_of"].type == Json.Type.int_
            && inputReq.json["best_of"].get!int == 1)
        {
            inputReq.json.remove("best_of");
        }
        req.writeJsonBody(inputReq.json);
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

void main()
{
    import std.process;

    auto router = new URLRouter;
    Conduit conduit;
    conduit.models["davinci-002"] = Model("https://api.openai.com/v1/completions",
            ["Authorization": "Bearer " ~ environment["OPENAI_API_KEY"]]);
    router.post("/v1/completions", &conduit.completions);
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    listenHTTP(settings, router);
    runApplication();
}
