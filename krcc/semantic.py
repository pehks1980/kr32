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
)

from symbols import SymbolTable, SymbolError


class SemanticError(Exception):
    """Raised when the source program violates semantic rules."""
    pass


class SemanticAnalyzer:

    def __init__(self):
        # Create a fresh symbol table for this compilation.
        self.symbols = SymbolTable()

    def analyze(self, translation_unit):
        """
        Analyze all functions in the translation unit.

        Currently our compiler supports a single main function.
        """

        for function in translation_unit.functions:

            # Enter the function scope.
            self.symbols.enter_scope()

            try:
                # Analyze statements in the function body.
                self.analyze_block(function.body)

            finally:
                # Always restore the previous scope,
                # even if semantic analysis reports an error.
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

        raise SemanticError(
            f"unsupported AST expression: {type(expression).__name__}"
        )