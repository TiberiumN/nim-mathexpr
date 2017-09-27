import math, strutils, tables
export tables

type
  MathFunction = proc(args: seq[float]): float

const
  ArgsErrorMsg = "Expected $1 arguments for function `$2`, got $3"
  AtLeastErrorMsg = "Function `$1` accepts at least one argument, got 0"
  CharErrorMsg = "Unexpected char $1 at pos $2"
  UnknownIdentMsg = "Unknown function, variable or constant `$1` at pos $2"

var functions* = newTable[string, MathFunction]()

proc eval*(data: string, vars: TableRef[string, float] = nil): float = 
  ## Evaluates math expression from string *data* and returns result as a float
  ## Has optional *vars* argument - table of variables - string: float
  let hasVars = (not vars.isNil) and vars.len > 0
  let hasFuncs = functions.len > 0

  var
    pos = 0  ## Current position
    ch = data[0]  ## Current char
  
  template nextChar = 
    ## Increments current position and gets next char
    inc pos
    ch = data[pos]
  
  template charError {.dirty.} = 
    # repr(ch) instead of $ to properly handle null-terminator
    raise newException(ValueError, CharErrorMsg % [repr(ch), $pos])

  proc eat(charToEat: char): bool {.inline.} = 
    ## Skips all whitespace characters, 
    ## checks if current character is *charToEat* and skips it
    while ch in Whitespace: nextChar()
    if ch == charToEat: 
      nextChar()
      result = true
  
  # We forward-declare these two procs because we have a recursive dependency
  proc parseExpression: float
  proc parseFactor: float

  proc getArgs(args = 0, funcName: string, zeroArgs = false): seq[float] = 
    result = @[]
    # If we have parens
    if eat('('):
      # While there are arguments left
      while ch != ')':
        # Parse an expression
        result.add parseExpression()
        # Skip ',' if we have it. With this we allow things like
        # max(1 2 3 4) or atan2(3 5)
        if ch == ',': nextChar()
      # Closing paren
      if not eat(')'):
        charError()
    else:
      # Parse a factor. It can't be an expression, because this
      # would provide wrong results: sqrt 100 * 70
      result.add parseFactor()
    # We check here if args count is provided and
    # it's the same as number of arguments
    # or we have 0 arguments but we don't allow zero arguments
    if (args != 0 and result.len != args):
      raise newException(
        ValueError, ArgsErrorMsg % [$args, funcName, $result.len]
      )
    elif (not zeroArgs and result.len == 0):
      raise newException(ValueError, AtLeastErrorMsg % [funcName])

  template getArgs(argsNum = 0, zeroArgs = false): untyped {.dirty.} = 
    getArgs(argsNum, funcName, zeroArgs)

  template getArg(): untyped {.dirty.} = 
    getArgs(1, funcName)[0]

  proc parseFactor: float = 
    # Unary + and -
    if eat('+'): return parseFactor()
    elif eat('-'): return -parseFactor()
    
    let startPos = pos
    
    # Parentheses
    if eat('('):
      result = parseExpression()
      if not eat(')'):
        charError()

    elif ch in IdentStartChars:
      while ch in IdentChars: nextChar()
      let funcName = data[startPos..<pos]

      # User-provided variables
      if hasVars:
        let data = vars.getOrDefault(funcName)
        if data != 0.0: return data
      
      # User-provided functions
      if hasFuncs:
        let data = functions.getOrDefault(funcName)
        if not data.isNil: return data(getArgs())

      case funcName
      # Built-in functions. Case statement is used for better performance
      of "abs": result = abs(getArg())
      of "acos", "arccos": result = arccos(getArg())
      of "asin", "arcsin": result = arcsin(getArg())
      of "atan", "arctan", "arctg": result = arctan(getArg())
      of "atan2", "arctan2":
        let args = getArgs(2)
        result = arctan2(args[0], args[1])
      of "ceil": result = ceil(getArg())
      of "cos": result = cos(getArg())
      of "cosh": result = cosh(getArg())
      of "exp": result = exp(getArg())
      of "sqrt": result = sqrt(getArg())
      of "sum": result = sum(getArgs())
      of "fac": result = float fac(int(getArg()))
      of "floor": result = floor(getArg())
      of "ln": result = ln(getArg())
      of "log", "log10": result = log10(getArg())
      of "log2": result = log2(getArg())
      of "max": result = max(getArgs())
      of "min": result = min(getArgs())
      of "ncr", "binom": 
        let args = getArgs(2)
        result = float binom(int args[0], int args[1])
      of "npr":
        let args = getArgs(2)
        result = float binom(int args[0], int args[1]) * fac(int args[1])
      of "pow":
        let args = getArgs(2)
        result = pow(args[0], args[1])
      of "sin": result = sin(getArg())
      of "sinh": result = sinh(getArg())
      of "tan": result = tan(getArg())
      of "tanh": result = tanh(getArg())
      # Built-in constants
      of "pi": result = PI
      of "tau": result = TAU
      of "e": result = E
      else: 
        raise newException(ValueError, UnknownIdentMsg % [$funcName, $pos])
    
    # Numbers (we allow things like .5)
    elif ch in {'0'..'9', '.'}:
      # Ugly checks to allow expressions like 10^5*5e-5
      # Maybe there's a better way?
      while ch in {'0'..'9', '.', 'e'} or 
        (ch == 'e' and data[pos+1] == '-') or 
        (data[pos-1] == 'e' and ch == '-' and data[pos+1] in {'0'..'9'}): 
        nextChar()
      result = 
        if ch == '.': parseFloat("0" & data[startPos..<pos])
        else: parseFloat(data[startPos..<pos])
    else:
      charError()
  
  proc parseTerm: float = 
    result = parseFactor()
    while true:
      if eat('*'): result *= parseFactor()
      elif eat('/'): result /= parseFactor()
      elif eat('%'):
        let val = parseFactor()
        when defined(JS):
          proc fmod(a, b: float): float = 
            asm """
            `result` = `a` % `b`;
            """
        result = result.fmod(val)
      elif eat('^'): result = result.pow(parseFactor())
      else: return

  proc parseExpression: float = 
    result = parseTerm()
    while true:
      if eat('+'): result += parseTerm()
      elif eat('-'): result -= parseTerm()
      else: return
  
  try:
    result = parseExpression()
  except OverflowError:
    return Inf
  # If we didn't process some characters in string
  if pos < data.len:
    charError()

template eval*(data: string, vars: openarray[tuple[key, val: typed]]): float = 
  ## Template which automatically converts *vars* openarray to table 
  eval(data, vars.newTable)