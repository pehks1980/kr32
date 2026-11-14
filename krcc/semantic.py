# semantic.py

from nodes import (
    IntLiteral,
    StringLiteral,
    Print,
    Return,
    VariableDeclaration,
    Variable,
    BinaryExpression,
    Assignment,
    While,
    DoWhile,
    CallExpression,
)

from symbols import SymbolTable, SymbolError


class SemanticError(Exception):
    """Raised when the source program violates semantic rules."""
    pass


class SemanticAnalyzer:

    def __init__(self):
        # Create a fresh symbol table for this compilation.
        self.symbols = SymbolTable()
        # Function namespace.
        self.functions = {}

    def register_functions(self, translation_unit):
        """
        Register all function definitions before analysing
        their bodies.
        """

        self.functions = {}

        #if there are no functions defined in the translation unit, we raise an error
        if not translation_unit.functions:
            raise SemanticError(
                "translation unit contains no function definitions"
            )
        # check for duplicate function definitions and unsupported return types

        for function in translation_unit.functions:

            # Reject duplicate definitions.
            if function.name in self.functions:
                raise SemanticError(
                    f"function '{function.name}' is already defined"
                )

            # Currently only int return types are supported.
            if function.return_type != "int":
                raise SemanticError(
                    f"unsupported return type '{function.return_type}' "
                    f"for function '{function.name}'"
                )
            #save the function return type, parameters and definition 
            # in the functions dictionary 
            # so that we can look it up later
            self.functions[function.name] = {
                "return_type": function.return_type,
                "parameters": function.parameters,
                "definition": function,
            }

        # Every executable must have main().
        if "main" not in self.functions:
            raise SemanticError(
                "program must define a 'main' function"
            )
    # we extend the semantic analysis to include function calls, 
    # but for now we will just check 
    # that the function is defined and that the number of 
    # arguments matches the number of parameters
    def analyze(self, translation_unit):
        """
        Analyze all functions in the translation unit.

        Pass 1: Register function definitions.
        Pass 2: Analyze function bodies.
        """

        # PASS 1: Register all functions.
        self.register_functions(translation_unit)

        # PASS 2: Analyze each function independently.
        # we also process the function parameters and add them to the symbol table        
        for function in translation_unit.functions:

            self.symbols.enter_scope()

            try:
                # Register function parameters as local symbols.
                for parameter in function.parameters:

                    if parameter.var_type != "int":
                        raise SemanticError(
                            f"unsupported parameter type "
                            f"'{parameter.var_type}' in function "
                            f"'{function.name}'"
                        )

                    try:
                        symbol = self.symbols.declare(
                            parameter.name,
                            parameter.var_type
                        )

                        # Attach the symbol to the parameter AST node.
                        parameter.symbol = symbol

                    except SymbolError as error:
                        raise SemanticError(str(error)) from error

                # Now parameters are visible inside the function body.
                self.analyze_block(function.body)

            finally:
                self.symbols.leave_scope()

        return translation_unit

    
    def analyze_block(self, statements):
        """
        Analyze a list of statements in the current scope.

        The function body uses the function scope.
        Nested loop bodies get their own scopes.
        """

        for statement in statements:
            self.analyze_statement(statement)

    def analyze_statement(self, statement):
        """Dispatch semantic analysis based on AST node type."""

        # -------------------------------------------------
        # Variable declaration
        # when a variable is declared, it is added to the symbol table as well
        # on statement.symbols, we store the symbols for each variable declared in this statement
        # Python dataclasses allow these attributes ie (.symbols) to be attached dynamically, 
        # provided your nodes don't use slots=True.
        # -------------------------------------------------

        if isinstance(statement, VariableDeclaration):
            statement.symbols = []

            for name in statement.names:
                try:
                    symbol = self.symbols.declare(name, statement.var_type)
                    statement.symbols.append(symbol)
                except SymbolError as error:
                    raise SemanticError(str(error)) from error

            return

        # -------------------------------------------------
        # Assignment
        # -------------------------------------------------

        if isinstance(statement, Assignment):
            # The destination variable must exist.
            symbol = self.symbols.lookup(statement.name)
            # variable not found - hence its not declared on this scope
            if symbol is None:
                raise SemanticError(
                    f"variable '{statement.name}' is not declared"
                )
            # Retain the symbol for the destination variable in the assignment statement.
            statement.symbol = symbol
            # Check all variables used in the expression.
            self.analyze_expression(statement.value)

            return

        # -------------------------------------------------
        # While loop
        # -------------------------------------------------
        if isinstance(statement, While):

            # Check variables used by the condition.
            self.analyze_expression(statement.condition)

            # The loop body has a nested scope.
            self.symbols.enter_scope()

            try:
                self.analyze_block(statement.body)
            finally:
                self.symbols.leave_scope()

            return

        # -------------------------------------------------
        # Do-while loop
        # -------------------------------------------------
        if isinstance(statement, DoWhile):

            # The body executes in its own scope.
            self.symbols.enter_scope()

            try:
                self.analyze_block(statement.body)
            finally:
                self.symbols.leave_scope()

            # The condition is checked after the body.
            # It can reference variables visible outside
            # the loop body, but not its local declarations.
            self.analyze_expression(statement.condition)

            return

        # -------------------------------------------------
        # Print statement
        # -------------------------------------------------
        if isinstance(statement, Print):

            for argument in statement.arguments:
                self.analyze_expression(argument)

            return

        # -------------------------------------------------
        # Return statement
        # -------------------------------------------------
        if isinstance(statement, Return):
            self.analyze_expression(statement.value)
            return

        raise SemanticError(
            f"unsupported AST statement: {type(statement).__name__}"
        )

    def analyze_expression(self, expression):
        """
        Recursively inspect an expression.

        Every variable reference must resolve to a declaration.
        """

        # Integer constants do not reference symbols.
        if isinstance(expression, IntLiteral):
            return

        # String literals do not reference symbols.
        if isinstance(expression, StringLiteral):
            return

        # Variable reference.
        if isinstance(expression, Variable):

            symbol = self.symbols.lookup(expression.name)

            if symbol is None:
                raise SemanticError(
                    f"variable '{expression.name}' is not declared"
                )
            # Retain the symbol for the variable reference in the AST node.
            expression.symbol = symbol
            return

        # Binary expression.
        if isinstance(expression, BinaryExpression):

            self.analyze_expression(expression.left)
            self.analyze_expression(expression.right)

            return

        # -------------------------------------------------
        # Function call
        #
        # Example:
        #     calculate(10, 20)
        #
        # Check that:
        #   1. The function has been defined.
        #   2. The number of arguments is correct.
        #   3. Every argument is a valid expression.
        # -------------------------------------------------
        if isinstance(expression, CallExpression):

            # Look up the function in the function registry.
            function = self.functions.get(expression.name)

            # The function must have been defined.
            if function is None:
                raise SemanticError(
                    f"function '{expression.name}' is not defined"
                )

            # Get the parameters declared by the function.
            parameters = function["parameters"]

            # Check that the caller supplied the correct
            # number of arguments.
            if len(expression.arguments) != len(parameters):
                raise SemanticError(
                    f"function '{expression.name}' expects "
                    f"{len(parameters)} argument(s), "
                    f"got {len(expression.arguments)}"
                )

            # Recursively analyse every argument.
            #
            # This is important because arguments can themselves
            # contain variables, binary expressions or function calls.
            for argument in expression.arguments:
                self.analyze_expression(argument)

            # Attach the function definition to the AST node.
            # Code generation can use this information later.
            expression.function = function["definition"]

            return


        
        raise SemanticError(
            f"unsupported AST expression: {type(expression).__name__}"
        )