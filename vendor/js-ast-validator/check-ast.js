var pretty = require("jsonpretty");

// basic predicates

function string(value) {
	return typeof(value) === "string";
}

function number(value) {
	return typeof(value) === "number";
}

function boolean(value) {
	return typeof(value) === "boolean";
}

function regExp(value) {
	return value instanceof RegExp;
}

function isValue(value) {
	return function (item) {
		return item === value;
	};
}

// define a nullable property
function maybe(specItem) {
	var checkFunc = handler(specItem);
	var maubeCheck = function (node) {
		return (node === null) || (node === undefined) || checkFunc(node);
	};
	maubeCheck.toString = function () {
		return "maybe(" + stringify(specItem) + ")";
	}
	return maubeCheck;
}

// defines a property which can follow one of several specs
function either(/* ...variadic... */) {
	var options = [];
	for (var i = 0; i < arguments.length; i++) {
		options.push(arguments[i]);
	}
	var handlers = options.map(handler);
	var checkFunc = function (node) {
		return handlers.some(function (checkFunc) {
			return checkFunc(node);
		});
	};
	checkFunc.toString = function () {
		return handlers.map(stringify).join(" | ");
	}
	return checkFunc;
}

// tests an AST node against a specification object
function verify(node, spec) {
  if (node == null) {
    return false;
  }
	if (spec.type && spec.type !== node.type) {
		// fail without an error for a type mismatch
		return false;
	}
	for (var key in spec) {
		// throw an error if the node does not 
		// match the spec for the type
		if (!handler(spec[key])(node[key])) {
			var e = "Invalid value for property '" + key + "' in " + node.type
				+ "\n    expected: " + stringify(spec[key])
				+ "\n    found: " + stringify(node[key]);
			throw Error(e);
		}
	}
	return true;
}

// generate a handler predicate from a spec rule
var handler = (function () {
	var typeHandlers = {
		string: function (str) {
			return function (value) {
				return value === str;
			};
		},
		object: function (obj) {
			if (obj instanceof Array) {
				return function (arr) {
					return arr instanceof Array && arr.every(handler(obj[0]));
				};
			}
			if (obj === null) {
				return isValue(null);
			}
			return function (node) {
				return verify(node, obj);
			};
		},
		function: function (func) {
			return func;
		},
		boolean: isValue
	};

	return function (value) {
		checkFunc = typeHandlers[typeof(value)];
		if (!checkFunc) {
			throw TypeError("Unknown type in specification");
		}
		return checkFunc(value);
	};
})();

// generate a string representation of a spec rule
function stringify(value) {
	switch (typeof(value)) {
		case "string":
			return '"' + value + '"';
		case "function":
			return value.name || value.toString();
		case "object":
			if (value === null) {
				return "null";
			}
			if (value instanceof Array) {
				return "[" + value.map(stringify) + "]";
			}
			return value.type || pretty(value);
		default:
			return "" + value;
	}
}

// creates a function which always return the same value
function always(value) {
	return function () {
		return value;
	}
}

// Entry point 

function program(node) {
	return verify(node, {
		type: "Program",
		body: [statement]
	});
}

// STATEMENTS

var statement = either(
	expressionStatement,
	variableDeclaration,
	functionDeclaration,
	blockStatement,
	ifStatement,
	returnStatement,
	switchStatement,
	throwStatement,
	tryStatement,
	whileStatement,
	doWhileStatement,
	forStatement,
	forInStatement,
	forOfStatement,
	breakStatement,
	continueStatement,
	emptyStatement, 
	withStatement,
	debuggerStatement,
	labeledStatement);

statement.toString = always("statement");

function emptyStatement(node) {
	return verify(node, {
		type: "EmptyStatement"
	});
}

function blockStatement(node) {
	return verify(node, {
		type: "BlockStatement",
		body: [statement]
	});
}

function expressionStatement(node) {
	return verify(node, {
		type: "ExpressionStatement",
		expression: expression
	});
}

function ifStatement(node) {
	return verify(node, {
		type: "IfStatement",
		test: expression,
		consequent: statement,
		alternate: maybe(statement)
	});
}

function labeledStatement(node) {
	return verify(node, {
		type: "LabeledStatement",
		label: identifier,
		body: statement
	});
}

function breakStatement(node) {
	return verify(node, {
		type: "BreakStatement",
		label: maybe(identifier)
	});
}

function continueStatement(node) {
	return verify(node, {
		type: "ContinueStatement",
		label: maybe(identifier)
	});
}

function withStatement(node) {
	return verify(node, {
		type: "WithStatement",
		object: expression,
		body: statement
	});
}

function switchStatement(node) {
	return verify(node, {
		type: "SwitchStatement",
		discriminant: expression,
		cases: [switchCase],
		lexical: maybe(boolean)
	});
}

function returnStatement(node) {
	return verify(node, {
		type: "ReturnStatement",
		argument: maybe(expression)
	});
}


function throwStatement(node) {
	return verify(node, {
		type: "ThrowStatement",
		argument: expression
	});
}

function tryStatement(node) {
	return verify(node, {
		type: "TryStatement",
		block: blockStatement,
		handler: maybe(catchClause),
		guardedHandlers: [catchClause],
		finalizer: maybe(blockStatement)
	});
}

function whileStatement(node) {
	return verify(node, {
		type: "WhileStatement",
		test: expression,
		body: statement
	});
}

function doWhileStatement(node) {
	return verify(node, {
		type: "DoWhileStatement",
		test: expression,
		body: statement
	});
}

function forStatement(node) {
	return verify(node, {
		type: "ForStatement",
		init: either(variableDeclaration, expression, null),
		test: maybe(expression),
		update: maybe(expression),
		body: statement
	});
}

function forInStatement(node) {
	return verify(node, {
		type: "ForInStatement",
		left: either(variableDeclaration, expression),
		right: expression,
		body: statement,
		each: boolean
	});
}

function forOfStatement(node) {
	return verify(node, {
		type: "ForOfStatement",
		left: either(variableDeclaration, expression),
		right: expression,
		body: statement
	});
}

function debuggerStatement(node) {
	return verify(node, {
		type: "DebuggerStatement"
	});
}

// DECLARATIONS

function functionDeclaration(node) {
	return verify(node, {
		type: "FunctionDeclaration",
		id: identifier,
		params: [pattern],
		defaults: [expression],
		body: blockStatement,
		rest: maybe(identifier),
		generator: boolean,
		expression: boolean
	});
}

function variableDeclaration(node) {
	return verify(node, {
		type: "VariableDeclaration",
		declarations: [variableDeclarator],
		kind: either("var", "let", "const")
	});
}

function variableDeclarator(node) {
	return verify(node, {
		type: "VariableDeclarator",
		id: pattern,
		init: maybe(expression)
	});
}

// EXPRESSIONS

var expression = either(
	identifier,
	literal,
	callExpression,
	assignmentExpression,
	unaryExpression,
	binaryExpression,
	logicalExpression,
	arrayExpression,
	objectExpression,
	memberExpression,
	functionExpression,
	conditionalExpression,
	thisExpression,
	arrowExpression,
	sequenceExpression,
	updateExpression,
	newExpression,
	yieldExpression);

expression.toString = always("expression");

function thisExpression(node) {
	return verify(node, {
		type: "ThisExpression"
	});
}

function arrayExpression(node) {
	return verify(node, {
		type: "ArrayExpression",
		elements: [expression]
	});
}

function objectExpression(node) {
	return verify(node, {
		type: "ObjectExpression",
		properties: [{
			key: either(literal, identifier),
			value: expression,
			kind: either("init", "get", "set")
		}]
	});
}

function functionExpression(node) {
	return verify(node, {
		type: "FunctionExpression",
		id: maybe(identifier),
		params: [pattern],
		defaults: [expression],
		rest: maybe(identifier),
		body: either(blockStatement, expression),
		generator: boolean,
		expression: boolean
	});
}

function arrowExpression(node) {
	return verify(node, {
		type: "ArrowExpression",
		id: maybe(identifier),
		params: [pattern],
		defaults: [expression],
		rest: maybe(identifier),
		body: either(blockStatement, expression),
		generator: boolean,
		expression: boolean
	});
}

function sequenceExpression(node) {
	return verify(node, {
		type: "SequenceExpression",
		expressions: [expression]
	});
}

function unaryExpression(node) {
	return verify(node, {
		type: "UnaryExpression",
		operator: unaryOperator,
		prefix: boolean,
		argument: expression
	});
}

function binaryExpression(node) {
	return verify(node, {
		type: "BinaryExpression",
		operator: binaryOperator,
		left: expression,
		right: expression
	});
}

function assignmentExpression(node) {
	return verify(node, {
		type: "AssignmentExpression",
		operator: assignmentOperator,
		left: expression,
		right: expression
	});
}

function updateExpression(node) {
	return verify(node, {
		type: "UpdateExpression",
		operator: updateOperator,
		prefix: boolean,
		argument: expression
	});
}

function logicalExpression(node) {
	return verify(node, {
		type: "LogicalExpression",
		operator: logicalOperator,
		left: expression,
		right: expression
	});
}

function conditionalExpression(node) {
	return verify(node, {
		type: "ConditionalExpression",
		test: expression,
		consequent: expression,
		alternate: expression
	});
}

function newExpression(node) {
	return verify(node, {
		type: "NewExpression",
		callee: expression,
		arguments: [expression]
	});
}

function callExpression(node) {
	return verify(node, {
		type: "CallExpression",
		callee: expression,
		arguments: [expression]
	});
}

function memberExpression(node) {
	return verify(node, {
		type: "MemberExpression",
		object: expression,
		property: either(identifier, expression),
		computed: boolean
	});
}

function yieldExpression(node) {
	return verify(node, {
		type: "YieldExpression",
		argument: expression
	});
}

// PATTERNS

var pattern = either(identifier, objectPattern, arrayPattern);

pattern.toString = always("pattern");

function objectPattern(node) {
	return verify(node, {
		type: "ObjectPattern",
		properties: [{
			key: either(literal, identifier), 
			value: pattern
		}]
	});
}

function arrayPattern(node) {
	return verify(node, {
		type: "ArrayPattern",
		elements: [maybe(pattern)]
	});
}

function identifier(node) {
	return verify(node, {
		type: "Identifier",
		name: string
	});
}

// CLAUSES

function switchCase(node) {
	return verify(node, {
		type: "SwitchCase",
		test: maybe(expression),
		consequent: either([statement], statement)
	});
}

function catchClause(node) {
	return verify(node, {
		type: "CatchClause",
		param: pattern,
		guard: maybe(expression),
		body: blockStatement
	});
}

function literal(node) {
	return verify(node, {
		type: "Literal",
		value: either(string, boolean, null, number, regExp)
	});
}

// OPERATORS

var unaryOperator = either("-", "+", "!", "~", "typeof", "void", "delete");

var binaryOperator = either(
	"==", 
	"!=", 
	"===", 
	"!==", 
	"<", 
	"<=", 
	">", 
	">=", 
	"<<", 
	">>", 
	">>>", 
	"+", 
	"-", 
	"*", 
	"/", 
	"%", 
	"|", 
	"^", 
	"&", 
	"in", 
	"instanceof", 
	"..");

var logicalOperator = either("||", "&&");

var assignmentOperator = either(
	"=",
	"+=",
	"-=",
	"*=",
	"/=",
	"%=",
	"<<=",
	">>=",
	">>>=",
	"|=",
	"^=",
	"&=");

var updateOperator = either("++", "--");



module.exports = function validateAST(node, nodeType) {
	nodeType = (nodeType || "program").toLowerCase();
	var nodeFunc = ({
		program: program,
		expression: expression,
		statement: statement
	})[nodeType];

	if (!nodeFunc) {
		throw Error("Unknown node type. Must be one of " +
			"'expression', 'statement' or 'program'");
	}

	if (!nodeFunc(node)) {
		throw Error("Root node in AST is not a valid " + nodeType);
	}
	return true;
}
