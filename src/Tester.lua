--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Array<T> = { [number]: T }
export type Map<T, Key> = { [T]: Key }

local EPSILON = 1e-5

local NODE_TYPE = {
	Detail = 0,
	Expect = 1,
	Attribute = 2
}
local NODE_ATTRIBUTE = {
	Skip = 0,
	Focus = 1,
	ToDo = 3
}

local Tester = {}
Tester.ClassName = "Tester"
Tester.__index = Tester

export type Tester = typeof(setmetatable({} :: {
	m_ModulesInfo: Array<TestModuleInfo>,
	m_Results: TestResults
}, Tester))

export type MessagePath = Array<string>
export type MessageList = Array<string>
export type TestResults = {
	-- Tests build time in milliseconds.
	BuildTime: number,
	-- Tests run time in milliseconds.
	RunTime: number,

	-- Number of test build errors.
	BuildErrorCount: number,
	-- Array containing paths to all build errors.
	BuildErrorPaths: Array<MessagePath>,
	-- Array containing lists with all build errors for a given path. The path for the error list BuildErrors[i] is BuildErrorPaths[i].
	BuildErrors: Array<MessageList>,

	-- Number of test debug messages.
	MessageCount: number,
	-- Array containing paths to all debug messages.
	MessagePaths: Array<MessagePath>,
	-- Array containing lists with all debug messages for a given path. The path for the message list Messages[i] is MessagePaths[i].
	Messages: Array<MessageList>,

	-- Number of successfully passed tests.
	PassedCount: number,
	-- Number of skipped tests.
	SkippedCount: number,
	-- Number of failed tests.
	FailedCount: number,
	-- Array containing paths to all run errors.
	RunErrorPaths: Array<MessagePath>,
	-- Array containing lists with all run errors for a given path. The path for the error list RunErrors[i] is RunErrorPaths[i].
	RunErrors: Array<MessageList>
}

type TestModuleInfo = {
	Name: string,
	Path: Array<string>,
	Callback: (environment: TestEnvironment, context: TestContext) -> ()
}

export type TestBuilder = (environment: TestEnvironment, context: TestContext) -> ()
export type TestContext = Map<any, any>
export type TestEnvironment = {
	--[[
		Runs the callback before building any of the tests.
	]]
	OnStart: (callback: () -> ()) -> (),
	--[[
		Runs the callback after building all of the tests.
	]]
	OnEnd: (callback: () -> ()) -> (),
	--[[
		Runs the callback each time a scope is entered using detail nodes.
	]]
	OnScopeEnter: (callback: () -> ()) -> (),
	--[[
		Runs the callback each time a scope is exited using detail nodes.
	]]
	OnScopeExit: (callback: () -> ()) -> (),

	--[[
		Creates a new scope with a given description.
	]]
	Detail: (detail: string, callback: () -> ()) -> (),
	--[[
		Creates a new test with a given value. A test validation check is expected after this node.
	]]
	Expect: (value: any) -> (),
	--[[
		Creates a new test which immediately fails.
	]]
	Fail: (message: string?) -> (),

	--[[
		Fails the test if the tested value is not equal to expect. A deep equality check is performed on tables.
	]]
	ToEqual: (expect: any) -> (),
	--[[
		Fails the test if the tested value's primitive type is not equal to expect.
	]]
	ToBeType: (expect: string) -> (),
	--[[
		Fails the test if the tested value's type is not equal to expect.
	]]
	ToBeTypeof: (expect: string) -> (),
	--[[
		Fails the test if tested function does not throw or if the error message does not contain expect.
	]]
	ToThrow: (expect: string?) -> (),
	--[[
		Fails the test if the tested value is equal to expect. A deep equality check is performed on tables.
	]]
	ToNotEqual: (expect: any) -> (),
	--[[
		Fails the test if the tested value's primitive type is equal to expect.
	]]
	ToNotBeType: (expect: string) -> (),
	--[[
		Fails the test if the tested value's type is equal to expect.
	]]
	ToNotBeTypeOf: (expect: string) -> (),
	--[[
		Fails the test if tested function throws or if the error message contains expect.
	]]
	ToNotThrow: (expect: string?) -> (),
	--[[
		Fails the test if the tested value is not within a distance of epsilon from expect.
	]]
	ToFuzzyEqual: (expect: number, epsilon: number?) -> (),
	--[[
		Fails the test if the tested value is within a distance of epsilon from expect.
	]]
	ToNotFuzzyEqual: (expect: number, epsilon: number?) -> (),
	--[[
		Fails the test if the tested value is not strictly greater than expect.
	]]
	ToBeGreater: (expect: number) -> (),
	--[[
		Fails the test if the tested value is not greater or equal to expect.
	]]
	ToBeGreaterOrEqual: (expect: number) -> (),
	--[[
		Fails the test if the tested value is not strictly smaller than expect.
	]]
	ToBeLess: (expect: number) -> (),
	--[[
		Fails the test if the tested value is not smaller or equal to expect.
	]]
	ToBeLessOrEqual: (expect: number) -> (),

	-- Debug functions
	--[[
		Skips a node and all of its children. Has priority over focus nodes.
	]]
	DebugSkip: () -> (),
	--[[
		Runs a node's tests and all of its descendants' tests, and ignores all of the other nodes in the same test module.
	]]
	DebugFocus: () -> (),
	--[[
		Adds a TODO message to a node.
	]]
	DebugToDo: (message: string) -> ()
}

type TestTreeNode = {
	Type: number,
	Attribute: number?,
	Errors: Array<string>?,
	Messages: Array<string>?,
	Name: string?,
	Children: Array<TestTreeNode>
}
type TestTreeRootNode = TestTreeNode & {
	Expand: (environment: TestEnvironment, context: TestContext) -> ()
}
type TestTreeDetailNode = TestTreeNode & {
	Expand: () -> ()
}
type TestTreeExpectNode = TestTreeNode & {
	Value: any,
	Expect: any,
	Check: (expect: any, value: any) -> (boolean, string?)
}

local function isTest(instance: Instance): boolean
	return instance:IsA("ModuleScript") and instance.Name:match("%.test$") ~= nil
end

local function getRelativePath(child: Instance, root: Instance): Array<string>
	local path = {}

	local parent: Instance? = child
	while parent ~= root and parent ~= nil do
		table.insert(path, parent.Name)
		parent = parent.Parent
	end
	table.insert(path, root.Name)

	return path
end

local function checkForTestModule(child: Instance, root: Instance, testModulesInfo: Array<TestModuleInfo>): ()	
	if isTest(child) then
		local path = getRelativePath(child, root)		

		local success, result = pcall(require, child)
		if not success then
			warn(`Skipped {table.concat(path, "/")}: {result}`)
			return

		elseif type(result) ~= "function" then
			warn(`Skipped {table.concat(path, "/")}: module does not return a function`)
			return
		end

		table.insert(testModulesInfo, {
			Name = child.Name,
			Path = path,
			Callback = result :: (TestEnvironment) -> ()
		})
	end
end

local function getTestModules(root: Instance): Array<TestModuleInfo>
	local testModulesInfo = {}
	checkForTestModule(root, root, testModulesInfo)
	for _, child in root:GetDescendants() do
		checkForTestModule(child, root, testModulesInfo)
	end

	return testModulesInfo
end

local TestNodeStack = {}
TestNodeStack.__index = TestNodeStack

type TestNodeStack = typeof(setmetatable({} :: {
	m_Stack: Array<TestTreeNode>
}, TestNodeStack))

function TestNodeStack.new(): TestNodeStack
	return setmetatable({
		m_Stack = {}
	}, TestNodeStack)
end

function TestNodeStack.GetLastNode(self: TestNodeStack): TestTreeNode
	return self.m_Stack[#self.m_Stack]
end

function TestNodeStack.PushNode(self: TestNodeStack, node: TestTreeNode): ()
	table.insert(self.m_Stack, node)
end

function TestNodeStack.PopNode(self: TestNodeStack): ()
	table.remove(self.m_Stack, #self.m_Stack)
end

local TestCallbackStack = {}
TestCallbackStack.__index = TestCallbackStack

export type TestCallbackStack = typeof(setmetatable({} :: {
	m_CallbacksReady: boolean,
	m_IsInScopeCallback: boolean,

	m_StartStack: Array<Array<() -> ()>>,
	m_EndStack: Array<Array<() -> ()>>,
	m_ScopeEnterStack: Array<Array<() -> ()>>,
	m_ScopeExitStack: Array<Array<() -> ()>>,
}, TestCallbackStack))

function TestCallbackStack.new(): TestCallbackStack
	return setmetatable({
		m_CallbacksReady = false,
		m_IsInScopeCallback = false,

		m_StartStack = {},
		m_EndStack = {},
		m_ScopeEnterStack = {},
		m_ScopeExitStack = {},
	}, TestCallbackStack)
end

function TestCallbackStack.AreCallbacksReady(self: TestCallbackStack): boolean
	return self.m_CallbacksReady
end

function TestCallbackStack.SetCallbacksReady(self: TestCallbackStack): ()
	self.m_CallbacksReady = true
end

function TestCallbackStack.IsInScopeCallback(self: TestCallbackStack): boolean
	return self.m_IsInScopeCallback
end

function TestCallbackStack.GetStartCallbacks(self: TestCallbackStack): Array<() -> ()>
	local callbacks = {}
	for _, stack in self.m_StartStack do
		for i = #stack, 1, -1 do
			table.insert(callbacks, stack[i])
		end
	end

	return callbacks
end

function TestCallbackStack.GetEndCallbacks(self: TestCallbackStack): Array<() -> ()>
	local callbacks = {}
	for _, stack in self.m_EndStack do
		for i = #stack, 1, -1 do
			table.insert(callbacks, stack[i])
		end
	end

	return callbacks
end

function TestCallbackStack.StartScopeEnterCallbacks(self: TestCallbackStack): Array<() -> ()>
	self.m_IsInScopeCallback = true

	local callbacks = {}
	for _, stack in self.m_ScopeEnterStack do
		for i = #stack, 1, -1 do
			table.insert(callbacks, stack[i])
		end
	end

	return callbacks
end

function TestCallbackStack.StartScopeExitCallbacks(self: TestCallbackStack): Array<() -> ()>
	self.m_IsInScopeCallback = true

	local callbacks = {}
	for _, stack in self.m_ScopeExitStack do
		for i = #stack, 1, -1 do
			table.insert(callbacks, stack[i])
		end
	end

	return callbacks
end

function TestCallbackStack.EndScopeCallbacks(self: TestCallbackStack): ()
	self.m_IsInScopeCallback = false
end

function TestCallbackStack.Push(self: TestCallbackStack): ()
	table.insert(self.m_StartStack, {})
	table.insert(self.m_EndStack, {})
	table.insert(self.m_ScopeEnterStack, {})
	table.insert(self.m_ScopeExitStack, {})
end

function TestCallbackStack.Pop(self: TestCallbackStack): ()
	table.remove(self.m_StartStack, #self.m_StartStack)
	table.remove(self.m_EndStack, #self.m_EndStack)
	table.remove(self.m_ScopeEnterStack, #self.m_ScopeEnterStack)
	table.remove(self.m_ScopeExitStack, #self.m_ScopeExitStack)
end

function TestCallbackStack.OnStart(self: TestCallbackStack, callback: () -> ()): ()
	table.insert(self.m_StartStack[#self.m_StartStack], callback)
end

function TestCallbackStack.OnEnd(self: TestCallbackStack, callback: () -> ()): ()
	table.insert(self.m_EndStack[#self.m_EndStack], callback)
end

function TestCallbackStack.OnScopeEnter(self: TestCallbackStack, callback: () -> ()): ()
	table.insert(self.m_ScopeEnterStack[#self.m_ScopeEnterStack], callback)
end

function TestCallbackStack.OnScopeExit(self: TestCallbackStack, callback: () -> ()): ()
	table.insert(self.m_ScopeExitStack[#self.m_ScopeExitStack], callback)
end

local function addError(stack: TestNodeStack, message: string): ()
	local lastNode = stack:GetLastNode()

	if lastNode.Errors == nil then
		lastNode.Errors = { message }
	else
		table.insert(lastNode.Errors, 1, message)
	end
end

local function addTracedError(stack: TestNodeStack, message: string): ()
	return addError(stack, debug.traceback(message, 2))
end

local function addMessage(stack: TestNodeStack, message: string): ()
	local lastNode = stack:GetLastNode()
	if lastNode.Messages == nil then
		lastNode.Messages = { message }
	else
		table.insert(lastNode.Messages, 1, message)
	end
end

local function validateExpectNode(stack: TestNodeStack, expect: any, check: (expect: any, value: any) -> boolean): boolean
	local lastNode = stack:GetLastNode()
	if lastNode.Type ~= NODE_TYPE.Expect then
		return false
	end

	(lastNode :: TestTreeExpectNode).Expect = expect;
	(lastNode :: TestTreeExpectNode).Check = check
	stack:PopNode()

	table.insert(stack:GetLastNode().Children, lastNode)

	return true
end

local function expectParameterAssert(stack: TestNodeStack, check: boolean): ()
	if not check and stack:GetLastNode().Type == NODE_TYPE.Expect then
		stack:PopNode()
	end
	return check
end

local function checkIncompleteExpectNode(stack: TestNodeStack): ()
	local lastNode = stack:GetLastNode()
	if lastNode.Type == NODE_TYPE.Expect and (lastNode :: TestTreeExpectNode).Check == nil then
		stack:PopNode()
		addTracedError(stack, "Encountered an Expect node without a validation check")
	end
end

local function checkInvalidAttributeNodes(stack: TestNodeStack): boolean
	local lastNode = stack:GetLastNode()
	if lastNode.Type ~= NODE_TYPE.Attribute then
		return false
	end

	repeat
		stack:PopNode()
		lastNode = stack:GetLastNode()
	until lastNode == nil or lastNode.Type ~= NODE_TYPE.Attribute

	return true
end

local function validateAttributeNodes(stack: TestNodeStack): Array<TestTreeNode>
	local attributeNodes = {}
	local lastNode = stack:GetLastNode()
	while lastNode ~= nil and lastNode.Type == NODE_TYPE.Attribute do
		stack:PopNode()
		table.insert(attributeNodes, lastNode)
		lastNode = stack:GetLastNode()
	end

	return attributeNodes
end

local function addFlag(attributes: number?, attribute: number): number
	return bit32.replace(attributes or 0, 1, attribute)
end
local function hasFlag(attributes: number?, attribute: number): boolean
	return if attributes == nil then false else bit32.btest(attributes, bit32.lshift(1, attribute))
end

local function setAttribute(stack: TestNodeStack, attributeNodes: Array<TestTreeNode>): ()
	local targetNode = stack:GetLastNode()

	for _, node in attributeNodes do
		local attribute = node.Attribute
		if attribute == NODE_ATTRIBUTE.ToDo then
			addMessage(stack, `TODO: {node.Name :: string}`)
			targetNode.Attribute = addFlag(targetNode.Attribute, NODE_ATTRIBUTE.ToDo)

		elseif attribute == NODE_ATTRIBUTE.Skip then
			addMessage(stack, "DebugSkip was used")
			targetNode.Attribute = addFlag(targetNode.Attribute, NODE_ATTRIBUTE.Skip)

		elseif attribute == NODE_ATTRIBUTE.Focus then
			addMessage(stack, "DebugFocus was used")
			targetNode.Attribute = addFlag(targetNode.Attribute, NODE_ATTRIBUTE.Focus)
		end
	end
end

local function runCallback(callback: (...any) -> (), ...: any): (boolean, string?)
	return xpcall(
		callback,
		function(message: string): string
			return debug.traceback(message, 2)
		end,
		...
	)
end

local function expandNode(stack: TestNodeStack, callbacks: TestCallbackStack, node: TestTreeDetailNode): ()
	callbacks:Push()

	local canExpand = true
	for _, scopeEnterCallback in callbacks:StartScopeEnterCallbacks() do
		local result; canExpand, result = runCallback(scopeEnterCallback)
		if not canExpand then
			addError(stack, `OnScopeEnter: {result}`)
		end
	end
	callbacks:EndScopeCallbacks()

	if canExpand then
		local success, expansionResult = runCallback(node.Expand)
		if not success then
			addError(stack, expansionResult :: string)
		end
	end

	for _, scopeExitCallback in callbacks:StartScopeExitCallbacks() do
		local success, result = runCallback(scopeExitCallback)
		if not success then
			addError(stack, `OnScopeExit: {result}`)
		end
	end
	callbacks:EndScopeCallbacks()

	checkIncompleteExpectNode(stack)
	if checkInvalidAttributeNodes(stack) then
		addTracedError(stack, "Encountered an attribute node at the end of the scope")
	end

	callbacks:Pop()
end

local function tableDeepEqualCheck(expect: Map<any, any>, tbl: Map<any, any>): boolean
	local expectLength, tblLength = 0, 0
	for _, _ in expect do
		expectLength += 1
	end
	for _, _ in tbl do
		tblLength += 1
	end
	if expectLength ~= tblLength then
		return false
	end

	for key, value in tbl do
		if type(value) == "table" then
			if type(expect[key]) ~= "table" or not tableDeepEqualCheck(expect[key], value) then
				return false
			end
		elseif value ~= expect[key] then
			return false
		end
	end

	return true
end

local function equalCheck(expect: any, value: any): (boolean, string?)
	if type(expect) == "table" then
		if type(value) ~= "table" or not tableDeepEqualCheck(expect, value) then
			return false, `ToEqual: expected {value} ({typeof(value)}) to equal {expect} ({typeof(expect)})`
		end
		return true, nil
	end

	if expect == value then
		return true, nil
	else
		return false, `ToEqual: expected {value} ({typeof(value)}) to equal {expect} ({typeof(expect)})`
	end
end

local function notEqualCheck(expect: any, value: any): (boolean, string?)
	if type(expect) == "table" then
		if type(value) == "table" and tableDeepEqualCheck(expect, value) then
			return false, `ToNotEqual: expected {value} ({typeof(value)}) to not equal {expect} ({typeof(expect)})`
		end
		return true, nil
	end

	if expect ~= value then
		return true, nil
	else
		return false, `ToNotEqual: expected {value} ({typeof(value)}) to not equal {expect} ({typeof(expect)})`
	end
end

local function typeCheck(expectType: string, value: any): (boolean, string?)
	local valueType = type(value)
	if valueType == expectType then
		return true, nil
	else
		return false, `ToBeType: expected type({value}) to equal {expectType}, got {valueType} instead`
	end
end

local function typeofCheck(expectType: string, value: any): (boolean, string?)
	local valueType = typeof(value)
	if valueType == expectType then
		return true, nil
	else
		return false, `ToBeTypeof: expected typeof({value}) to equal {expectType}, got {valueType} instead`
	end
end

local function notTypeCheck(expectType: string, value: any): (boolean, string?)
	if type(value) ~= expectType then
		return true, nil
	else
		return false, `ToNotBeType: expected type({value}) to not equal {expectType}`
	end
end

local function notTypeofCheck(expectType: string, value: any): (boolean, string?)
	if typeof(value) ~= expectType then
		return true, nil
	else
		return false, `ToNotBeTypeof: expected typeof({value}) to not equal {expectType}`
	end
end

local function greaterCheck(expect: number, value: number): (boolean, string?)
	local valueType = type(value)
	if valueType ~= "number" then
		return false, `ToBeGreater: number value expected, got {valueType} instead`
	end

	if value > expect then
		return true, nil
	else
		return false, `ToBeGreater: {value} > {expect} expected`
	end
end

local function greaterOrEqualCheck(expect: number, value: number): (boolean, string?)
	local valueType = type(value)
	if valueType ~= "number" then
		return false, `ToBeGreaterOrEqual: number value expected, got {valueType} instead`
	end

	if value >= expect then
		return true, nil
	else
		return false, `ToBeGreaterOrEqual: {value} >= {expect} expected`
	end
end

local function smallerCheck(expect: number, value: number): (boolean, string?)
	local valueType = type(value)
	if valueType ~= "number" then
		return false, `ToBeSmaller: number value expected, got {valueType} instead`
	end

	if value < expect then
		return true, nil
	else
		return false, `ToBeSmaller: {value} < {expect} expected`
	end
end

local function smallerOrEqualCheck(expect: number, value: number): (boolean, string?)
	local valueType = type(value)
	if valueType ~= "number" then
		return false, `ToBeSmallerOrEqual: number value expected, got {valueType} instead`
	end

	if value <= expect then
		return true, nil
	else
		return false, `ToBeSmallerOrEqual: {value} <= {expect} expected`
	end
end

local function toThrowCheck(expect: string?, value: (...any) -> ...any): (boolean, string?)
	local valueType = type(value)
	if valueType ~= "function" then
		return false, `ToThrow: function value expected, got {valueType} instead`
	end

	local success, result = pcall(value)
	if success then
		if expect == nil then
			return false, `ToThrow: expected function to throw, it succeeded instead`
		else
			return false, `ToThrow: expected function to throw a message containing {expect}, it succeeded instead`
		end
	end

	if expect == nil or result:find(expect, 1, true) ~= nil then
		return true, nil
	else
		return false, `ToThrow: expected function to throw a message containing {expect}, it threw: {result}`
	end
end

local function toNotThrowCheck(expect: string?, value: (...any) -> ...any): (boolean, string?)
	local valueType = type(value)
	if valueType ~= "function" then
		return false, `ToNotThrow: function value expected, got {valueType} instead`
	end

	local success, result = pcall(value)
	if success then
		if expect == nil then
			return true, nil
		else
			return false, `ToNotThrow: expected function to throw a message which does not contain {expect}, it succeeded instead`
		end
	end

	if expect == nil then
		return false, `ToNotThrow: expected function to succeed, it threw: {result}`
	end

	if result:find(expect, 1, true) == nil then
		return true, nil
	else
		return false, `ToNotThrow: expected function to throw a message which does not contain {expect}, it threw: {result}`
	end
end

local function alwaysFailCheck(expect: string?, value: nil): (boolean, string?)
	return false, if expect == nil then `Fail:` else `Fail: {expect}`
end

local function createTestEnvironment(stack: TestNodeStack, callbacks: TestCallbackStack): TestEnvironment
	local environment = {}

	function environment.OnStart(callback: () -> ()): ()
		callbacks:OnStart(callback)
	end
	function environment.OnEnd(callback: () -> ()): ()
		callbacks:OnEnd(callback)
	end
	function environment.OnScopeEnter(callback: () -> ()): ()
		callbacks:OnScopeEnter(callback)
	end
	function environment.OnScopeExit(callback: () -> ()): ()
		callbacks:OnScopeExit(callback)
	end

	function environment.Detail(detail: string, callback: () -> ()): ()
		if type(detail) ~= "string" then
			addTracedError(stack, `Detail argument #1: string expected, got {type(detail)}`)
			return
		end
		if type(callback) ~= "function" then
			addTracedError(stack, `Detail argument #2: function expected, got {type(callback)}`)
			return
		end
		if callbacks:IsInScopeCallback() then
			addTracedError(stack, "Cannot call Detail in OnScopeEnter or OnScopeExit")
			return
		end
		checkIncompleteExpectNode(stack)

		local attributeNodes = validateAttributeNodes(stack)
		local node = {
			Type = NODE_TYPE.Detail,
			Name = detail,
			Expand = callback,
			Children = {}
		}
		table.insert(stack:GetLastNode().Children, node)
		stack:PushNode(node)

		setAttribute(stack, attributeNodes)
		if callbacks:AreCallbacksReady() then
			expandNode(stack, callbacks, node)
		end

		stack:PopNode()
	end
	function environment.Expect(value: any): ()
		checkIncompleteExpectNode(stack)

		local attributeNodes = validateAttributeNodes(stack)
		local node = {
			Type = NODE_TYPE.Expect,
			Value = value,
			Children = {}
		}
		stack:PushNode(node)

		setAttribute(stack, attributeNodes)
	end
	function environment.Fail(message: string?): ()
		checkIncompleteExpectNode(stack)

		local attributeNodes = validateAttributeNodes(stack)
		local node = {
			Type = NODE_TYPE.Expect,
			Check = alwaysFailCheck,
			Expect = message,
			Value = nil,
			Children = {}
		}
		table.insert(stack:GetLastNode().Children, node)

		setAttribute(stack, attributeNodes)
	end

	function environment.ToEqual(expect: any): ()
		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToEqual")
		end
		if not validateExpectNode(stack, expect, equalCheck) then
			addTracedError(stack, "No Expect node to check against with ToEqual")
		end
	end
	function environment.ToBeType(expect: string): ()
		if not expectParameterAssert(stack, type(expect) == "string") then
			addTracedError(stack, `ToBeType argument: string expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToBeType")
		end
		if not validateExpectNode(stack, expect, typeCheck) then
			addTracedError(stack, "No Expect node to check against with ToBeType")
		end
	end
	function environment.ToBeTypeof(expect: string): ()
		if not expectParameterAssert(stack, type(expect) == "string") then
			addTracedError(stack, `ToBeTypeof argument: string expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToBeTypeOf")
		end
		if not validateExpectNode(stack, expect, typeofCheck) then
			addTracedError(stack, "No Expect node to check against with ToBeTypeof")
		end
	end
	function environment.ToThrow(expect: string?): ()
		if expect ~= nil and not expectParameterAssert(stack, type(expect) == "string") then
			addTracedError(stack, `ToThrow argument: string? expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToThrow")
		end
		if not validateExpectNode(stack, expect, toThrowCheck) then
			addTracedError(stack, "No Expect node to check against with ToThrow")
		end
	end
	function environment.ToNotEqual(expect: any): ()
		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToNotEqual")
		end
		if not validateExpectNode(stack, expect, notEqualCheck) then
			addTracedError(stack, "No Expect node to check against with ToNotEqual")
		end
	end
	function environment.ToNotBeType(expect: string): ()
		if not expectParameterAssert(stack, type(expect) == "string") then
			addTracedError(stack, `ToNotBeType argument: string expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToNotBeType")
		end
		if not validateExpectNode(stack, expect, notTypeCheck) then
			addTracedError(stack, "No Expect node to check against with ToNotBeType")
		end
	end
	function environment.ToNotBeTypeOf(expect: string): ()
		if not expectParameterAssert(stack, type(expect) == "string") then
			addTracedError(stack, `ToNotBeTypeof argument: string expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToNotBeTypeof")
		end
		if not validateExpectNode(stack, expect, notTypeofCheck) then
			addTracedError(stack, "No Expect node to check against with ToNotBeTypeof")
		end
	end
	function environment.ToNotThrow(expect: string?): ()
		if expect ~= nil and not expectParameterAssert(stack, type(expect) == "string") then
			addTracedError(stack, `ToNotThrow argument: string? expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToNotThrow")
		end
		if not validateExpectNode(stack, expect, toNotThrowCheck) then
			addTracedError(stack, "No Expect node to check against with ToNotThrow")
		end
	end

	function environment.ToFuzzyEqual(expect: number, epsilon: number?): ()
		if not expectParameterAssert(stack, type(expect) == "number") then
			addTracedError(stack, `ToFuzzyEqual argument #1: number expected, got {type(expect)}`)
			return
		end
		if not expectParameterAssert(stack, epsilon == nil or type(epsilon) == "number") then
			addTracedError(stack, `ToFuzzyEqual argument #2: number expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToFuzzyEqual")
		end

		local function check(expect: number, value: number): (boolean, string?)
			local valueType = type(value)
			if valueType ~= "number" then
				return false, `ToFuzzyEqual: number value expected, got {valueType} instead`
			end

			local finalEpsilon = epsilon or EPSILON
			if math.abs(expect - value) <= finalEpsilon then
				return true, nil
			else
				return false, `ToFuzzyEqual: expected {value} to be in the range [{expect - finalEpsilon}, {expect + finalEpsilon}]`
			end
		end
		if not validateExpectNode(stack, expect, check) then
			addTracedError(stack, "No Expect node to check against with ToFuzzyEqual")
		end
	end
	function environment.ToNotFuzzyEqual(expect: number, epsilon: number?): ()
		if not expectParameterAssert(stack, type(expect) == "number") then
			addTracedError(stack, `ToNotFuzzyEqual argument #1: number expected, got {type(expect)}`)
			return
		end
		if not expectParameterAssert(stack, epsilon == nil or type(epsilon) == "number") then
			addTracedError(stack, `ToNotFuzzyEqual argument #2: number expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToNotFuzzyEqual")
		end

		local function check(expect: number, value: number): (boolean, string?)
			local valueType = type(value)
			if valueType ~= "number" then
				return false, `ToNotFuzzyEqual: number value expected, got {valueType} instead`
			end

			local finalEpsilon = epsilon or EPSILON
			if math.abs(expect - value) > finalEpsilon then
				return true, nil
			else
				return false, `ToFuzzyEqual: expected {value} to not be in the range [{expect - finalEpsilon}, {expect + finalEpsilon}]`
			end
		end
		if not validateExpectNode(stack, expect, check) then
			addTracedError(stack, "No Expect node to check against with ToNotFuzzyEqual")
		end
	end
	function environment.ToBeGreater(expect: number): ()
		if not expectParameterAssert(stack, type(expect) == "number") then
			addTracedError(stack, `ToBeGreater argument: number expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToBeGreater")
		end
		if not validateExpectNode(stack, expect, greaterCheck) then
			addTracedError(stack, "No Expect node to check against with ToBeGreater")
		end
	end
	function environment.ToBeGreaterOrEqual(expect: number): ()
		if not expectParameterAssert(stack, type(expect) == "number") then
			addTracedError(stack, `ToBeGreaterOrEqual argument: number expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToBeGreaterOrEqual")
		end
		if not validateExpectNode(stack, expect, greaterOrEqualCheck) then
			addTracedError(stack, "No Expect node to check against with ToBeGreaterOrEqual")
		end
	end
	function environment.ToBeLess(expect: number): ()
		if not expectParameterAssert(stack, type(expect) == "number") then
			addTracedError(stack, `ToBeLess argument: number expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToBeLess")
		end
		if not validateExpectNode(stack, expect, smallerCheck) then
			addTracedError(stack, "No Expect node to check against with ToBeLess")
		end
	end
	function environment.ToBeLessOrEqual(expect: number): ()
		if not expectParameterAssert(stack, type(expect) == "number") then
			addTracedError(stack, `ToBeLessOrEqual argument: number expected, got {type(expect)}`)
			return
		end

		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an Attribute node before ToBeLessOrEqual")
		end
		if not validateExpectNode(stack, expect, smallerOrEqualCheck) then
			addTracedError(stack, "No Expect node to check against with ToBeLessOrEqual")
		end
	end

	function environment.DebugSkip(): ()
		checkIncompleteExpectNode(stack)

		local node = {
			Type = NODE_TYPE.Attribute,
			Attribute = NODE_ATTRIBUTE.Skip,
			Children = {}
		}
		stack:PushNode(node)
	end
	function environment.DebugFocus(): ()
		checkIncompleteExpectNode(stack)

		local node = {
			Type = NODE_TYPE.Attribute,
			Attribute = NODE_ATTRIBUTE.Focus,
			Children = {}
		}
		stack:PushNode(node)
	end
	function environment.DebugToDo(message: string): ()
		if type(message) ~= "string" then
			addTracedError(stack, `DebugToDo argument: string expected, got {type(message)}`)
			return
		end

		checkIncompleteExpectNode(stack)

		local node = {
			Type = NODE_TYPE.Attribute,
			Attribute = NODE_ATTRIBUTE.ToDo,
			Name = message,
			Children = {}
		}
		stack:PushNode(node)
	end

	return environment
end

local function expandRootNodes(tree: TestTreeNode, rootNodes: Array<TestTreeRootNode>): ()
	local stack = TestNodeStack.new()
	local callbacks = TestCallbackStack.new()
	local environment = createTestEnvironment(stack, callbacks)
	local context = {}

	stack:PushNode(tree.Children[1])
	callbacks:Push()

	for _, rootNode in rootNodes do
		stack:PushNode(rootNode)

		-- Do an initial expansion to gather scope callbacks
		local success, result = runCallback(rootNode.Expand, environment, context)
		if not success then
			addTracedError(stack, result :: string)
		end

		checkIncompleteExpectNode(stack)
		if checkInvalidAttributeNodes(stack) then
			addTracedError(stack, "Encountered an attribute node at the end of the scope")
		end

		stack:PopNode()
	end

	local canStart = true
	for _, startCallback in callbacks:GetStartCallbacks() do
		local result; canStart, result = runCallback(startCallback)
		if not canStart then
			addError(stack, `OnStart: {result}`)
		end
	end

	if canStart then
		callbacks:SetCallbacksReady()

		for _, rootNode in rootNodes do
			stack:PushNode(rootNode)

			local canExpand = true
			for _, scopeEnterCallback in callbacks:StartScopeEnterCallbacks() do
				local result; canExpand, result = runCallback(scopeEnterCallback)
				if not canExpand then
					addError(stack, `{rootNode.Name} OnScopeEnter: {result}`)
				end
			end
			callbacks:EndScopeCallbacks()

			if canExpand then
				for _, childNode in rootNode.Children do
					if childNode.Type == NODE_TYPE.Detail then
						stack:PushNode(childNode)
						expandNode(stack, callbacks, childNode :: TestTreeDetailNode)
						stack:PopNode()
					end
				end
			end

			for _, scopeExitCallback in callbacks:StartScopeExitCallbacks() do
				local success, result = runCallback(scopeExitCallback)
				if not success then
					addError(stack, `{rootNode.Name} OnScopeExit: {result}`)
				end
			end
			callbacks:EndScopeCallbacks()

			stack:PopNode()
		end
	end

	for _, endCallback in callbacks:GetEndCallbacks() do
		local success, result = runCallback(endCallback)
		if not success then
			addError(stack, `OnEnd: {result}`)
		end
	end

	callbacks:Pop()
	stack:PopNode()
end

local function createNodeTree(modulesInfo: Array<TestModuleInfo>): TestTreeNode
	local tree: TestTreeNode = {
		Type = NODE_TYPE.Detail,
		Children = {}
	}
	local rootNodes = {}

	for _, testInfo in modulesInfo do
		local currentNode = tree

		for i = #testInfo.Path, 1, -1 do
			local childNode
			for _, child in currentNode.Children do
				if child.Name == testInfo.Path[i] then
					childNode = child
					break
				end
			end

			if childNode == nil then
				childNode = {
					Type = NODE_TYPE.Detail,
					Name = testInfo.Path[i],
					Children = {}
				}
				table.insert(currentNode.Children, childNode)
			end
			currentNode = childNode
		end

		(currentNode :: TestTreeRootNode).Expand = testInfo.Callback
		table.insert(rootNodes, currentNode :: TestTreeRootNode)
	end

	expandRootNodes(tree, rootNodes)

	return tree
end

local function collectBuildMessages(rootNode: TestTreeNode, results: TestResults, temporaryPath: Array<string>): ()
	for _, childNode in rootNode.Children do
		if childNode.Name ~= nil then
			table.insert(temporaryPath, childNode.Name)
		end

		if childNode.Messages ~= nil then
			table.insert(results.MessagePaths, table.clone(temporaryPath))
			table.insert(results.Messages, childNode.Messages)

			results.MessageCount += #childNode.Messages
		end

		if childNode.Type == NODE_TYPE.Detail then
			if childNode.Errors ~= nil then
				table.insert(results.BuildErrorPaths, table.clone(temporaryPath))
				table.insert(results.BuildErrors, childNode.Errors)

				results.BuildErrorCount += #childNode.Errors
			end

			collectBuildMessages(childNode, results, temporaryPath)
		end

		if childNode.Name ~= nil then
			table.remove(temporaryPath)
		end
	end
end

local function getSkippedChildrenCount(rootNode: TestTreeNode): number
	local count = 0
	for _, childNode in rootNode.Children do
		if childNode.Type == NODE_TYPE.Expect then
			count += 1

		elseif childNode.Type == NODE_TYPE.Detail then
			count += getSkippedChildrenCount(rootNode)
		end
	end

	return count
end

local function collectTestResults(rootNode: TestTreeNode, results: TestResults, temporaryPath: Array<string>, hasFocusAttributes: boolean, parentHasFocus: boolean): ()
	local childErrors = {}

	for _, childNode in rootNode.Children do
		if hasFlag(childNode.Attribute, NODE_ATTRIBUTE.Skip) then
			if childNode.Type == NODE_TYPE.Expect then
				results.SkippedCount += 1

			elseif childNode.Type == NODE_TYPE.Detail then
				results.SkippedCount += getSkippedChildrenCount(childNode)
			end

			continue
		end

		if childNode.Name ~= nil then
			table.insert(temporaryPath, childNode.Name)
		end

		local hasFocus = parentHasFocus or hasFlag(childNode.Attribute, NODE_ATTRIBUTE.Focus)

		if childNode.Type == NODE_TYPE.Expect then
			if hasFocusAttributes and not hasFocus then
				results.SkippedCount += 1

				continue
			end

			local expect = childNode :: TestTreeExpectNode
			local success, result = expect.Check(expect.Expect, expect.Value)
			if success then
				results.PassedCount += 1
			else
				results.FailedCount += 1

				table.insert(childErrors, result :: string)
			end

		elseif childNode.Type == NODE_TYPE.Detail then
			collectTestResults(childNode, results, temporaryPath, hasFocusAttributes, hasFocus)
		end

		if childNode.Name ~= nil then
			table.remove(temporaryPath)
		end
	end

	if #childErrors > 0 then
		table.insert(results.RunErrorPaths, table.clone(temporaryPath))
		table.insert(results.RunErrors, childErrors)
	end
end

local function findFocusAttributes(rootNode: TestTreeNode): boolean
	local hasFocusAttributes = false
	for _, childNode in rootNode.Children do
		if hasFlag(childNode.Attribute, NODE_ATTRIBUTE.Focus) then
			hasFocusAttributes = true
		end
		if childNode.Type == NODE_TYPE.Detail then
			hasFocusAttributes = hasFocusAttributes or findFocusAttributes(childNode)
		end
	end

	return hasFocusAttributes
end

local function getMilliseconds(): number
	return os.clock() * 1000
end

--[[
	Creates a Tester. Runs tests on descendants of testsRoot which are ModuleScripts with the suffix ".test".
]]
function Tester.new(testsRoot: Instance): Tester
	local results = {
		BuildTime = 0,
		RunTime = 0,

		BuildErrorCount = 0,
		BuildErrorPaths = {},
		BuildErrors = {},

		MessageCount = 0,
		MessagePaths = {},
		Messages = {},

		PassedCount = 0,
		SkippedCount = 0,
		FailedCount = 0,
		RunErrorPaths = {},
		RunErrors = {}
	}

	local start = getMilliseconds()

	local temporaryPath = {}
	local modulesInfo = getTestModules(testsRoot)
	local tree = createNodeTree(modulesInfo)
	collectBuildMessages(tree, results, temporaryPath)

	results.BuildTime = math.floor((getMilliseconds() - start) * 1000) / 1000

	start = getMilliseconds()

	local hasFocusAttributes = findFocusAttributes(tree)
	collectTestResults(tree, results, temporaryPath, hasFocusAttributes, false)

	results.RunTime = math.floor((getMilliseconds() - start	) * 1000) / 1000

	return setmetatable({
		m_ModulesInfo = modulesInfo,
		m_Results = results
	}, Tester)
end

--[[
	Returns information for all test modules before building the tests.
]]
function Tester.GetModulesInfo(self: Tester): Array<TestModuleInfo>
	return self.m_ModulesInfo
end

--[[
	Returns the test results.
]]
function Tester.GetResults(self: Tester): TestResults
	return self.m_Results
end

--[[
	Prints the results in the output.
]]
function Tester.PrintResultsDefault(self: Tester): ()
	local results = self.m_Results
	local output = {
		"",
		"=============== Test results ===============",
		"",
		`Build Time: {results.BuildTime}ms`,
		`Run Time: {results.RunTime}ms`,
		"",
		`{results.PassedCount} Passed Test(s)`,
		`{results.FailedCount} Failed Test(s)`,
		`{results.SkippedCount} Skipped Test(s)`,
		""
	}

	if results.MessageCount > 0 then
		local messageString = `{results.MessageCount} Debug Message(s):\n`

		for index, messages in results.Messages do
			local path = results.MessagePaths[index]

			for index, key in path do
				messageString ..= `{('\t'):rep(index - 1)}\\{key}\n`
			end
			for _, message in messages do
				messageString ..= `{('\t'):rep(#path)}- {message}\n`
			end
		end

		table.insert(output, messageString)
	end

	if results.BuildErrorCount == 0 then
		table.insert(output, "Successfully built tests")
	else
		local buildErrorsString = `{results.BuildErrorCount} Build Error(s):\n`
		for index, errors in results.BuildErrors do
			local path = results.BuildErrorPaths[index]

			for index, key in path do
				buildErrorsString ..= `{('\t'):rep(index - 1)}\\{key}\n`
			end
			for _, error in errors do
				buildErrorsString ..= `{('\t'):rep(#path)}- {error}\n`
			end
		end

		table.insert(output, buildErrorsString)
	end

	if results.FailedCount == 0 then
		table.insert(output, "Successfully ran tests")
	else
		local runErrorsString = `{results.FailedCount} Run Error(s):\n`
		for index, errors in results.RunErrors do
			local path = results.RunErrorPaths[index]

			for index, key in path do
				runErrorsString ..= `{('\t'):rep(index - 1)}\\{key}\n`
			end
			for _, error in errors do
				runErrorsString ..= `{('\t'):rep(#path)}- {error}\n`
			end
		end

		table.insert(output, runErrorsString)
	end
	
	table.insert(output, "")
	table.insert(output, "============================================")
	
	print(table.concat(output, "\n"))
end

return Tester