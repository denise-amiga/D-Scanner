/*******************************************************************************
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 ******************************************************************************/


module main;


import std.file;
import std.stdio;
import std.algorithm;
import std.conv;
import std.array;
import std.path;
import std.regex;
import std.getopt;
import std.parallelism;
import types;
import tokenizer;
import parser;
import langutils;
import autocomplete;
import highlighter;

pure bool isLineOfCode(TokenType t)
{
	switch(t)
	{
	case TokenType.semicolon:
	case TokenType.tWhile:
	case TokenType.tIf:
	case TokenType.tFor:
	case TokenType.tForeach:
	case TokenType.tCase:
		return true;
	default:
		return false;
	}
}

/**
 * Loads any import directories specified in /etc/dmd.conf.
 * Bugs: Only works on Linux
 * Returns: the paths specified as -I options in /etc/dmd.conf
 */
string[] loadDefaultImports()
{
version(linux)
{
	string path = "/etc/dmd.conf";
	if (!exists(path))
		return [];
	string[] rVal;
	auto file = File(path, "r");
	foreach(char[] line; file.byLine())
	{
		if (!line.startsWith("DFLAGS"))
			continue;
		while ((line = line.find("-I")).length > 0)
		{
			auto end = std.string.indexOf(line, " ");
			auto importDir = line[2 .. end].idup;
			rVal ~= importDir;
			line = line[end .. $];
		}
	}
	return rVal;
}
else
{
	return [];
}
}

/**
 * Returns: the absolute path of the given module, or null if it could not be
 *     found.
 */
string findAbsPath(string[] dirs, string moduleName)
{
	// For file names
	if (endsWith(moduleName, ".d") || endsWith(moduleName, ".di"))
	{
		if (startsWith(moduleName, "/"))
			return moduleName;
		else
			return getcwd() ~ "/" ~ moduleName;
	}

	// Try to find the file name from a module name like "std.stdio"
	foreach(dir; dirs)
	{
		string fileLocation = dir ~ "/" ~ replace(moduleName, ".", "/");
		string dfile = fileLocation ~ ".d";
		if (exists(dfile) && isFile(dfile))
		{
			return dfile;
		}
		if (exists(fileLocation  ~ ".di") && isFile(fileLocation  ~ ".di"))
		{
			return fileLocation ~ ".di";
		}
	}
	stderr.writeln("Could not locate import ", moduleName, " in ", dirs);
	return null;
}

string[] loadConfig()
{
	string path = expandTilde("~/.dscanner");
	string[] dirs;
	if (exists(path))
	{
		auto f = File(path, "r");
		scope(exit) f.close();

		auto trimRegex = ctRegex!("\\s*$");
		foreach(string line; lines(f))
		{
			dirs ~= replace(line, trimRegex, "");
		}
	}
	foreach(string importDir; loadDefaultImports()) {
		dirs ~= importDir;
	}
	return dirs;
}


void main(string[] args)
{
	string[] importDirs;
	bool sloc;
	bool dotComplete;
	bool json;
	bool parenComplete;
	bool highlight;
	getopt(args, "I", &importDirs, "dotComplete", &dotComplete, "sloc", &sloc,
		"json", &json, "parenComplete", &parenComplete, "highlight", &highlight);

	importDirs ~= loadConfig();

	if (sloc)
	{
		writeln(args[1..$].map!(a => a.readText().tokenize())().joiner()
			.count!(a => isLineOfCode(a.type))());
		return;
	}

	if (highlight)
	{
		highlighter.highlight(args[1].readText().tokenize(IterationStyle.EVERYTHING));
		return;
	}

	if (dotComplete || parenComplete)
	{
		auto tokens = args[1].readText().tokenize();
		auto mod = parseModule(tokens);
		auto context = new CompletionContext(mod);
		foreach (im; parallel(mod.imports))
		{
			auto p = findAbsPath(importDirs, im);
			if (p is null || !p.exists())
				continue;
			context.addModule(p.readText().tokenize().parseModule());
		}
		auto complete = AutoComplete(tokens, context);
		if (parenComplete)
			writeln(complete.parenComplete(to!size_t(args[2])));
		else if (dotComplete)
			writeln(complete.dotComplete(to!size_t(args[2])));
		return;
	}

	if (json)
	{
		auto tokens = tokenize(readText(args[1]));
		auto mod = parseModule(tokens);
		mod.writeJSONTo(stdout);
	}
}
