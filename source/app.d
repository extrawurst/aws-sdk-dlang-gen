import std.stdio;
import std.json;
import std.file;
import std.array;
import std.format;

//TODO: support optional and required in shapes

auto output = appender!string;

struct Alias
{
	JSONValue json;
	string type;
}

struct Operation
{
	string name;
	//JSONValue[string] http;
	string input;
	string output;
	string doc;
}

static struct Shapes
{
	static JSONValue[string] lists;
	static JSONValue[string] maps;
	static JSONValue[string] enums;
	static JSONValue[string] structs;
	static Alias[string] aliases;
}

Operation[] ops;
string serviceName;

void main(string[] args)
{
	string content = readText(args[1]);

	auto json = parseJSON(content);

	foreach (key, obj; json.object)
	{
		if (key == "shapes")
			parseShapes(obj);
		if (key == "operations")
			parseOps(obj);
	}

	assert("metadata" in json.object);
	serviceName = json["metadata"]["serviceAbbreviation"].str;

	writeOutput();

	writeln(output.data);
}

void parseShapes(JSONValue json)
{
	foreach (key, obj; json.object)
	{
		parseShape(key, obj);
	}
}

void parseOps(JSONValue json)
{
	foreach (key, obj; json.object)
	{
		parseOp(key, obj);
	}
}

void parseOp(string name, JSONValue json)
{
	Operation op;

	assert(name == json["name"].str);
	assert("POST" == json["http"]["method"].str);
	assert("/" == json["http"]["requestUri"].str);

	if (auto doc = "documentation" in json)
		op.doc = doc.str;

	op.name = name;

	op.output = json["output"]["shape"].str;
	op.input = json["input"]["shape"].str;

	ops ~= op;
}

void parseShape(string name, JSONValue json)
{
	auto type = json["type"].str;

	if ("exception" in json)
	{
		stderr.writefln("exception ignored: '%s'", name);
		return;
	}

	switch (type)
	{
	case "string":
		if ("enum" in json)
			Shapes.enums[name] = json;
		else
			Shapes.aliases[name] = Alias(json, "string");
		break;
	case "long":
		Shapes.aliases[name] = Alias(json, "long");
		break;
	case "integer":
		Shapes.aliases[name] = Alias(json, "int");
		break;
	case "boolean":
		Shapes.aliases[name] = Alias(json, "bool");
		break;
	case "double":
		Shapes.aliases[name] = Alias(json, "double");
		break;
	case "list":
		Shapes.lists[name] = json;
		break;
	case "structure":
		Shapes.structs[name] = json;
		break;
	case "map":
		Shapes.maps[name] = json;
		break;
	default:
		stderr.writefln("unknown shape found: '%s' (falling back to string type)", type);
		Shapes.aliases[name] = Alias(json, "string");
		break;
	}
}

void writeOutput()
{
	foreach (key, json; Shapes.enums)
	{
		if ("documentation" in json)
			output ~= format("///%s\n", json["documentation"].str);

		output ~= format("enum %s {\n", key);
		foreach (entryJson; json["enum"].array)
			output ~= format("\t%s, \n", entryJson.str);
		output ~= "}\n\n";
	}

	foreach (key, aliasEntry; Shapes.aliases)
	{
		if ("documentation" in aliasEntry.json)
			output ~= format("///%s\n", aliasEntry.json["documentation"].str);

		output ~= format("alias %s = %s;\n\n", key, aliasEntry.type);
	}

	foreach (key, json; Shapes.lists)
	{
		if ("documentation" in json)
			output ~= format("///%s\n", json["documentation"].str);

		auto type = json["member"]["shape"].str;
		output ~= format("alias %s = %s[];\n\n", key, type);
	}

	foreach (key, json; Shapes.maps)
	{
		if ("documentation" in json)
			output ~= format("///%s\n", json["documentation"].str);

		auto keytype = json["key"]["shape"].str;
		auto valtype = json["value"]["shape"].str;
		output ~= format("alias %s = %s[%s];\n\n", key, valtype, keytype);
	}

	foreach (key, json; Shapes.structs)
	{
		if ("documentation" in json)
			output ~= format("///%s\n", json["documentation"].str);

		output ~= format("struct %s {\n", key);

		foreach (key, structMemberJson; json["members"].object)
		{
			auto type = structMemberJson["shape"].str;
			if ("documentation" in structMemberJson)
				output ~= format("\t///%s\n", structMemberJson["documentation"].str);
			output ~= format("\t%s %s;\n\n", key, type);
		}

		output ~= "}\n\n";
	}

	output ~= format("interface %s {\n", serviceName);

	foreach (op; ops)
	{
		if (op.doc.length > 0)
			output ~= format("\t///%s\n", op.doc);

		output ~= format("\t%s %s(%s);\n\n", op.output, op.name, op.input);
	}

	output ~= "}\n";
}
