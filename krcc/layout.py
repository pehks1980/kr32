
from nodes import (
    VariableDeclaration,
    While,
    DoWhile,
    Assignment,
    Print,
    Return,
    BinaryExpression,
    Variable,
)


class LayoutError(Exception):
    pass


class StorageLayout:
    """
    Assigns stack-frame offsets to local variables.

    KR32 stack convention:
        - Stack grows downward.
        - SP decreases when allocating memory.
        - FP is the stable reference for local variables.
        - Local variables use negative FP-relative offsets.

    Current supported types:
        int = 4 bytes
    """

    TYPE_SIZES = {
        "int": 4,
    }

    def __init__(self):
        self.offset = 0
        self.allocated_symbols = set()

    def layout(self, translation_unit):
        """
        Calculate storage layout for every function.
        """

        for function in translation_unit.functions:
            self.offset = 0
            self.allocated_symbols = set()

            self.layout_block(function.body)

            # Round frame size up to 4-byte alignment.
            frame_size = (self.offset + 3) & ~3

            function.frame_size = frame_size

        return translation_unit

    def layout_block(self, statements):
        for statement in statements:
            self.layout_statement(statement)

    def layout_statement(self, statement):

        if isinstance(statement, VariableDeclaration):
            self.layout_declaration(statement)
            return

        if isinstance(statement, While):
            self.layout_block(statement.body)
            return

        if isinstance(statement, DoWhile):
            self.layout_block(statement.body)
            return

        if isinstance(statement, Assignment):
            self.layout_expression(statement.value)
            return

        if isinstance(statement, Print):
            for argument in statement.arguments:
                self.layout_expression(argument)
            return

        if isinstance(statement, Return):
            self.layout_expression(statement.value)
            return

        raise LayoutError(
            f"Unsupported statement: {type(statement).__name__}"
        )

    def layout_declaration(self, declaration):

        if not hasattr(declaration, "symbols"):
            raise LayoutError(
                "Declaration has no semantic symbol information. "
                "Run semantic analysis first."
            )

        for symbol in declaration.symbols:

            # Avoid allocating the same symbol twice.
            symbol_id = id(symbol)

            if symbol_id in self.allocated_symbols:
                continue

            size = self.TYPE_SIZES.get(symbol.var_type)

            if size is None:
                raise LayoutError(
                    f"Unsupported variable type: {symbol.var_type}"
                )

            self.offset += size

            # Stack grows downward.
            symbol.stack_offset = -self.offset

            self.allocated_symbols.add(symbol_id)

    def layout_expression(self, expression):

        if isinstance(expression, (Variable,)):
            return

        if isinstance(expression, BinaryExpression):
            self.layout_expression(expression.left)
            self.layout_expression(expression.right)
            return
