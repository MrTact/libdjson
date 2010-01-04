/**
 * LibDJSONcontains functions and classes for reading, parsing, and writing JSON
 * documents.
 *
 * Copyright:	(c) 2009 William K. Moore, III (nyphbl8d (at) gmail (dot) com, opticron on freenode)
 * Authors:	William K. Moore, III
 * License:	Boost Software License - Version 1.0 - August 17th, 2003

 Permission is hereby granted, free of charge, to any person or organization
 obtaining a copy of the software and accompanying documentation covered by
 this license (the "Software") to use, reproduce, display, distribute,
 execute, and transmit the Software, and to prepare derivative works of the
 Software, and to permit third-parties to whom the Software is furnished to
 do so, all subject to the following:

 The copyright notices in the Software and this entire statement, including
 the above license grant, this restriction and the following disclaimer,
 must be included in all copies of the Software, in whole or in part, and
 all derivative works of the Software, unless such copies or derivative
 works are solely in the form of machine-executable object code generated by
 a source language processor.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.

 * Standards:	Attempts to conform to the subset of Javascript require to implement the JSON Specification
 */

module libdjson.json;
version(Tango) {
	import tango.text.Util:isspace=isSpace,stripl=triml,strip=trim,stripr=trimr,find=locatePattern,split,replace=substitute;
	import tango.text.convert.Integer:tostring=toString,atoi=toInt;
	import tango.text.convert.Float:tostring=toString,atof=toFloat;
	import tango.text.Ascii:icmp=icompare,cmp=compare;
	import tango.io.Stdout:writef=Stdout;
	import tango.text.Regex;
	alias char[] string;
	string regrep(string input,string pattern,string delegate(string) translator) {
		string tmpdel(RegExpT!(char) m) {
			return translator(m.match(0));
		}
		auto rgxp = Regex(pattern,"g");
		return rgxp.replaceAll(input,&tmpdel);
	}
} else {
	version(D_Version2) {
		import std.conv:to;
		import std.string:strip,stripr,stripl,split,replace,find=indexOf,cmp,icmp,atoi,atof;
	} else {
		import std.string:tostring=toString,strip,stripr,stripl,split,replace,find,cmp,icmp,atoi,atof;
	}
	import std.stdio;
	import std.ctype:isspace;
	import std.regexp:sub,RegExp;
	//import std.utf:toUTF8;
	string regrep(string input,string pattern,string delegate(string) translator) {
		string tmpdel(RegExp m) {
			return translator(m.match(0));
		}
		return std.regexp.sub(input,pattern,&tmpdel,"g");
	}
}

/**
 * Read an entire string into a JSON tree.
 * This defaults to stripping all whitespace for a speed gain (less objects created), but can be forced to preserve whitespace using the second parameter.
 * Example:
 * --------------------------------
 * string jsonstring = "{\"firstName\": \"John\",\"lastName\": \"Smith\",\"address\": {\"streetAddress\": \"21 2nd Street\",\"city\": \"New York\",\"state\": \"NY\",\"postalCode\": 10021},\"phoneNumbers\": [{ \"type\": \"home\", \"number\": \"212 555-1234\" },{ \"type\": \"fax\", \"number\": \"646 555-4567\" }],\"newSubscription\": false,\"companyName\": null }";
 * auto jnode = jsonstring.readJSON();
 * xmlstring = jnode.toString;
 * // ensure that the string doesn't mutate after a second reading, it shouldn't
 * debug(json)writef("libdjson.json unit test\n");
 * assert(jsonstring.readJSON().toString == jsonstring);
 * 
 * --------------------------------
 * Returns: A JSONObject with no name that is the root of the document that was read.
 * Throws: JSONError on any parsing errors.
 */
JSONObject readJSON(string src) {
	string pointcpy = src;
	auto root = new JSONObject();
	try {
		root.parse(src);
	} catch (JSONError e) {
		writef("Caught exception from input string:\n",pointcpy,"\n");
		throw e;
	}
	return root;
}

/// An exception thrown on JSON parsing errors.
class JSONError : Exception {
	// Throws an exception with an error message.
	this(string msg) {
		super(msg);
	}
}

/// This is the interface implemented by all classes that represent JSON objects.
interface JSONType {
	string toString();
	/// The parse method of this interface should ALWAYS be destructive, removing things from the front of source as it parses.
	void parse(ref string source);
}
/**
 * JSONObject represents a single JSON object node and has methods for 
 * adding children.  All methods that make changes modify this
 * JSONObject rather than making a copy, unless otherwise noted.  Many methods
 * return a self reference to allow cascaded calls.
 * Example:
 * --------------------------------
 * // Create a JSON tree, and write it to a file.
 * /// XXX this needs an example
 * --------------------------------*/
class JSONObject:JSONType {
	// XXX this needs opApply for foreach
	this(){}
	protected JSONType[string] _children;
	void opIndexAssign(JSONType type,string key) {
		_children[key] = type;
	}
	JSONType opIndex(string key) {
		return _children[key];
	}
	int length() {return _children.length;}
	string toString() {
		string ret;
		ret ~= "{";
		foreach (key,val;_children) {
			ret ~= key~":"~val.toString~",";
		}
		// rip off the trailing comma, we don't need it
		if (ret.length > 1) ret = ret[0..$-1];
		ret ~= "}";
		return ret;
	}
	/// This function parses a JSONObject out of a string
	void parse(ref string source) in { assert(source[0] == '{'); } body {
		// only put the incoming check in the in, because it should have already been checked if we're this far
		// rip off the leading {
		source = stripl(source[1..$]);
		while (source[0] != '}') {
			if (source[0] != '"') throw new JSONError("Missing open quote for element key before: "~source);
			// use JSONString class to help us out here (read, I'm lazy :D)
			auto jstr = new JSONString();
			jstr.parse(source);
			source = stripl(source);
			if (source[0] != ':') throw new JSONError("Missing ':' after keystring in object before: "~source);
			source = stripl(source[1..$]);
			_children[jstr.get] = parseHelper(source);
			source = stripl(source);
			// handle end cases
			if (source[0] == '}') continue;
			if (source[0] != ',') throw new JSONError("Missing continuation via ',' or end of JSON object via '}' before "~source);
			// rip the , in preparation for the next loop
			source = stripl(source[1..$]);
			// make sure we don't have a ",}", since I'm assuming it's not allowed
			if (source[0] == '}') throw new JSONError("Empty array elements (',' followed by '}') are not allowed. Fill the space or remove the comma.\nThis error occurred before: "~source);
		}
		// rip off the } and be done with it
		source = stripl(source[1..$]);
	}
}

/// JSONArray represents a single JSON array, capable of being heterogenous
class JSONArray:JSONType {
	// XXX this needs opApply for foreach
	this(){}
	protected JSONType[] _children;
	void opCatAssign(JSONType child) {
		_children ~= child;
	}
	JSONType opIndex(int key) {
		return _children[key];
	}
	int length() {return _children.length;}
	string toString() {
		string ret;
		ret ~= "[";
		foreach (val;_children) {
			ret ~= val.toString~",";
		}
		// rip off the trailing comma, we don't need it
		if (ret.length > 1) ret = ret[0..$-1];
		ret ~= "]";
		return ret;
	}
	/// This function parses a JSONArray out of a string
	void parse(ref string source) in { assert(source[0] == '['); } body {
		// only put the incoming check in the in, because it should have already been checked if we're this far
		// rip off the leading [
		source = stripl(source[1..$]);
		while (source[0] != ']') {
			source = stripl(source[1..$]);
			_children ~= parseHelper(source);
			source = stripl(source);
			// handle end cases
			if (source[0] == ']') continue;
			if (source[0] != ',') throw new JSONError("Missing continuation via ',' or end of JSON array via ']' before "~source);
			// rip the , in preparation for the next loop
			source = stripl(source[1..$]);
			// make sure we don't have a ",]", since I'm assuming it's not allowed
			if (source[0] == ']') throw new JSONError("Empty array elements (',' followed by ']') are not allowed. Fill the space or remove the comma.\nThis error occurred before: "~source);
		}
		// rip off the ] and be done with it
		source = stripl(source[1..$]);
	}
}

/// JSONString represents a JSON string.  Internal representation is escaped for faster parsing and JSON generation.
class JSONString:JSONType {
	this(){}
	this(string data) {_data = data;}
	protected string _data;
	void set(string data) {_data = JSONEncode(data);}
	string get() {return JSONDecode(_data);}
	string toString() {
		return _data;
	}
	/// This function parses a JSONArray out of a string
	void parse(ref string source) in { assert(source[0] == '"'); } body {
		// only put the incoming check in the in, because it should have already been checked if we're this far
		// rip off the leading [
		source = source[1..$];
		// scan to find the closing quote
		int bscount = 0;
		int sliceloc = -1;
		for(int i = 0;i<source.length;i++) {
			switch(source[i]) {
			case '\\':
				bscount++;
				continue;
			case '"':
				// if the count is even, backslashes cancel and we have the end of the string, otherwise cascade
				if (bscount%2 == 0) {
					break;
				}
			default:
				bscount = 0;
				continue;
			}
			// we have reached the terminating case! huzzah!
			sliceloc = i;
		}
		// take care of failure to find the end of the string
		if (sliceloc == -1) throw new JSONError("Unable to find the end of the JSON string starting here: "~source);
		_data = source[0..sliceloc];
		// eat the " that is known to be there
		source = stripl(source[sliceloc+1..$]);
	}
}

/// JSONBoolean represents a JSON boolean value.
class JSONBoolean:JSONType {
	this(){}
	this(bool data) {_data = data;}
	void set(bool data) {_data = data;}
	bool get() {return _data;}
	protected bool _data;
	string toString() {
		if (_data) return "true";
		return "false";
	}
	/// This function parses a JSONBoolean out of a string
	void parse(ref string source) {
		if (source[0..4] == "true") {
			source = stripl(source[4..$]);
		} else if (source[0..5] == "false") {
			source = stripl(source[5..$]);
		} else throw new JSONError("Could not parse JSON boolean variable from: "~source);
	}
}

/// JSONNull represents a JSON null value.
class JSONNull:JSONType {
	// XXX should this have a getter and a setter at all?
	this(){}
	string toString() {
		return "null";
	}
	/// This function parses a JSONNull out of a string.  Really, it just rips "null" off the beginning of the string and eats whitespace.
	void parse(ref string source) in { assert(source[0..4] == "null"); } body {
		source = stripl(source[4..$]);
	}
}

/// JSONNumber represents any JSON numeric value.
class JSONNumber:JSONType {
	this(){}
	this(real data) {_data = data;}
	void set(real data) {_data = data;}
	real get() {return _data;}
	protected real _data;
	string toString() {
		return tostring(_data);
	}
	/// This function parses a JSONNumber out of a string
	void parse(ref string source) {
		// this parser sucks...
		int i = 0;
		// check for leading minus sign
		if (source[i] == '-') i++;
		// sift through whole numerics
		if (source[i] == '0') {
			i++;
		} else if (source[i] <= '9' && source[i] >= '1') {
			while (source[i] >= '0' && source[i] <= '9') i++;
		} else throw new JSONError("A numeric parse error occurred while parsing the numeric beginning at: "~source);
		// if the next char is not a '.', we know we're done with fractional parts 
		if (source[i] == '.') {
			i++;
			while (source[i] >= '0' && source[i] <= '9') i++;
		}
		// if the next char is e or E, we're poking at an exponential
		if (source[i] == 'e' || source[i] == 'E') {
			i++;
			if (source[i] == '-' || source[i] == '+') i++;
			while (source[i] >= '0' && source[i] <= '9') i++;
		}
		_data = atof(source[0..i]);
		source = stripl(source[i..$]);
	}
}

private JSONType parseHelper(ref string source) {
	JSONType ret;
	switch(source[0]) {
	case '{':
		ret = new JSONObject();
		break;
	case '[':
		ret = new JSONArray();
		break;
	case '"':
		ret = new JSONString();
		break;
	case '-','0','1','2','3','4','5','6','7','8','9':
		ret = new JSONNumber();
		break;
	default:
		// you need at least 5 characters for true or null and a closing character, this makes the slice for false safe
		if (source.length < 5) throw new JSONError("There seems to be a problem parsing the remainder of the text from this point: "~source);
		if (source[0..4] == "null") ret = new JSONNull();
		else if (source[0..4] == "true" || source[0..5] == "false") ret = new JSONBoolean();
		else throw new JSONError("Unable to determine type of next element beginning: "~source);
		break;
	}
	ret.parse(source);
	return ret;
}

/// Perform JSON escapes on a string
string JSONEncode(string src) {
	string tempStr;
        tempStr = replace(src    , "\\", "\\\\");
        tempStr = replace(tempStr, "\"", "\\\"");
        return tempStr;
}

/// Unescape a JSON string
string JSONDecode(string src) {
	string tempStr;
        tempStr = replace(src    , "\\\\", "\\");
        tempStr = replace(tempStr, "\\\"", "\"");
        tempStr = replace(tempStr, "\\/", "/");
        tempStr = replace(tempStr, "\\n", "\n");
        tempStr = replace(tempStr, "\\r", "\r");
        tempStr = replace(tempStr, "\\f", "\f");
        tempStr = replace(tempStr, "\\t", "\t");
        tempStr = replace(tempStr, "\\b", "\b");
	// take care of hex character entities
	tempStr = regrep(tempStr,"\\u[0-9a-fA-F]{4};",(string m) {
		auto cnum = m[3..$-1];
		dchar dnum = hex2dchar(cnum[1..$]);
		return quickUTF8(dnum);
	});
        return tempStr;
}

string quickUTF8(dchar dachar) {
	char[] ret;
	if (dachar <= 0x7F) {
		ret.length = 1;
		ret[0] = cast(char) dachar;
	} else if (dachar <= 0x7FF) {
		ret.length = 2;
		ret[0] = cast(char)(0xC0 | (dachar >> 6));
		ret[1] = cast(char)(0x80 | (dachar & 0x3F));
	} else if (dachar <= 0xFFFF) {
		ret.length = 3;
		ret[0] = cast(char)(0xE0 | (dachar >> 12));
		ret[1] = cast(char)(0x80 | ((dachar >> 6) & 0x3F));
		ret[2] = cast(char)(0x80 | (dachar & 0x3F));
	} else if (dachar <= 0x10FFFF) {
		ret.length = 4;
		ret[0] = cast(char)(0xF0 | (dachar >> 18));
		ret[1] = cast(char)(0x80 | ((dachar >> 12) & 0x3F));
		ret[2] = cast(char)(0x80 | ((dachar >> 6) & 0x3F));
		ret[3] = cast(char)(0x80 | (dachar & 0x3F));
	} else {
	    assert(0);
	}
	return cast(string)ret;
}
private dchar hex2dchar (string hex) {
	dchar res;
	foreach(digit;hex) {
		res <<= 4;
		res |= toHVal(digit);
	}
	return res;
}

private dchar toHVal(char digit) {
	if (digit >= '0' && digit <= '9') {
		return digit-'0';
	}
	if (digit >= 'a' && digit <= 'f') {
		return digit-'a';
	}
	if (digit >= 'A' && digit <= 'F') {
		return digit-'A';
	}
	return 0;
}

unittest {
	auto root = new JSONObject();
	auto arr = new JSONArray();
	arr ~= new JSONString("da blue teeths!\"\\");
	root["what is that on your ear?"] = arr;
	root["my pants"] = new JSONString("are on fire");
	root["i am this many"] = new JSONNumber(10.253);
	string jstr = root.toString;
	std.stdio.writefln("Generated JSON string: %s",jstr);
	std.stdio.writefln("Regenerated JSON string: %s",readJSON(jstr).toString);
}

