# symbols.py

from dataclasses import dataclass


class SymbolError(Exception):
    """Raised when a symbol-table operation is invalid."""
    pass


@dataclass
class Symbol:
    # Identifier name, for example "counter".
    name: str

    # Declared C type, initially only "int".
    var_type: str

    # Nesting depth of the scope containing this symbol.
    scope_level: int

    # Storage information will be assigned later.
    # Example: -4 means FP - 4.
    #stack_offset: int #| None = None


class SymbolTable:

    def __init__(self):
        # Each dictionary represents one scope.
        #
        # Index 0 is the outermost scope.
        # The last dictionary is always the current scope.
        self.scopes = [{}]

    def enter_scope(self):
        """
        Create a new nested scope.

        Variables declared here are visible in this scope
        and its child scopes.
        """
        self.scopes.append({})

    def leave_scope(self):
        """
        Exit the current scope.

        Variables declared in the scope being removed
        are no longer visible.
        """
        if len(self.scopes) == 1:
            raise SymbolError("cannot remove global scope")

        self.scopes.pop()

    def declare(self, name, var_type):
        """
        Declare a symbol in the current scope.

        A variable cannot be declared twice in the same scope.
        An inner scope may, however, shadow an outer variable.
        """

        current_scope = self.scopes[-1]

        if name in current_scope:
            raise SymbolError(
                f"variable '{name}' already declared in this scope"
            )

        symbol = Symbol(
            name=name,
            var_type=var_type,
            scope_level=len(self.scopes) - 1,
        )

        current_scope[name] = symbol

        return symbol

    def lookup(self, name):
        """
        Search for a symbol from the innermost scope outward.

        This implements normal lexical scope lookup.

        An inner variable takes precedence over a variable
        with the same name in an outer scope.
        """

        for scope in reversed(self.scopes):
            if name in scope:
                return scope[name]

        return None