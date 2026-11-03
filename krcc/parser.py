from nodes import (
    IntLiteral,
    Print,
    Return,
    StringLiteral,
    Function,
    TranslationUnit,
    VariableDeclaration,
    Variable,
    Assignment,
    BinaryExpression,
    While,
    DoWhile,
)


# Parser-specific exception.
# We keep syntax errors separate from lexical errors.
class ParserError(Exception):
    pass


class Parser:
    def __init__(self, tokens):
        # Tokens produced by our lexer.
        self.tokens = tokens

        # Index of the token currently being examined.
        self.pos = 0

    def current(self):
        # Return the current token without consuming it.
        return self.tokens[self.pos]

    def advance(self):
        # Consume the current token and move to the next one.
        token = self.current()

        # Do not move beyond EOF.
        if token.kind != "EOF":
            self.pos += 1

        return token

    def expect(self, kind, value=None):
        """
        Require the current token to have a particular kind
        and optionally a particular value.

        For example:
            expect("KEYWORD", "int")
            expect("PUNCT", ";")
            expect("IDENT")
        """

        token = self.current()

        # First check the token category.
        if token.kind != kind:
            raise ParserError(
                f"{token.line}:{token.column}: "
                f"expected {kind}, got {token.kind} ({token.value!r})"
            )

        # If a specific value was requested, check that too.
        if value is not None and token.value != value:
            raise ParserError(
                f"{token.line}:{token.column}: "
                f"expected {value!r}, got {token.value!r}"
            )

        # The token matches. Consume it and return it.
        return self.advance()

    def parse_integer(self, token):
        # Convert the original spelling into a Python integer.
        #
        # Decimal:     "42"   -> 42
        # Hexadecimal: "0x2A" -> 42
        #
        # We handle the formats explicitly so that decimal
        # numbers are always interpreted as decimal.
        if token.value.lower().startswith("0x"):
            return int(token.value, 16)

        return int(token.value, 10)

    def parse_translation_unit(self):
        """
        Parse the complete source file.

        Our first compiler version supports one function only.
        EOF ensures that no unexpected tokens remain afterwards.
        """

        functions = []

        # Parse the function defined in the source.
        functions.append(self.parse_function())

        # The complete input must now be consumed.
        self.expect("EOF")

        return TranslationUnit(functions=functions)

    def parse_function(self):
        """
        Grammar:
            function := "int" IDENT "(" "void" ")" block
        """

        # Function return type.
        return_type = self.expect("KEYWORD", "int").value

        # Function name.
        name = self.expect("IDENT").value

        # Opening parenthesis.
        self.expect("PUNCT", "(")

        # Only main(void) is supported for now.
        self.expect("KEYWORD", "void")

        # Closing parenthesis.
        self.expect("PUNCT", ")")

        # Parse the function body.
        body = self.parse_block()

        return Function(
            return_type=return_type,
            name=name,
            parameters=[],
            body=body,
        )

    def parse_block(self):
        """
        Grammar:
            block := "{" statement* "}"
        """

        self.expect("PUNCT", "{")

        statements = []
        while not (
            self.current().kind == "PUNCT"
            and self.current().value == "}"
        ):
            if self.current().kind == "EOF":
                token = self.current()
                raise ParserError(
                    f"{token.line}:{token.column}: expected '}}' before end of file"
                )
            statements.append(self.parse_statement())

        self.expect("PUNCT", "}")

        return statements

    def parse_statement(self):
        token = self.current()

        # Variable declaration: int x, y, z;
        if token.kind == "KEYWORD" and token.value == "int":
            return self.parse_variable_declaration()
        
        # Return statement
        if token.kind == "KEYWORD" and token.value == "return":
            return self.parse_return_statement()

         # Normal while loop.
        if token.kind == "KEYWORD" and token.value == "while":
            return self.parse_while_statement()

        # Do-while loop.
        if token.kind == "KEYWORD" and token.value == "do":
            return self.parse_do_while_statement()
        
        # printf statement
        if token.kind == "IDENT" and token.value == "printf":
            return self.parse_printf_statement()

         # -------------------------------------------------
        # Assignment statement
        #
        # An identifier at the beginning of a statement
        # currently represents an assignment.
        #
        # Example:
        #     x = 100;
        # -------------------------------------------------
        if token.kind == "IDENT":
            return self.parse_assignment()
        
        # error in statement
        raise ParserError(
            f"{token.line}:{token.column}: unsupported statement "
            f"starting with {token.value!r}"
        )

    def parse_printf_statement(self):
        """
        Parse a printf statement.

        Grammar:
            printf_statement :=
                "printf" "(" STRING ("," expression)* ")" ";"

        Examples:
            printf("Hello\n");
            printf("%d\n", x);
            printf("%d + %d = %d\n", x, y, x + y);

        The first argument must be a string literal.
        Additional arguments are parsed as expressions.
        """

        # -------------------------------------------------
        # Consume the printf identifier and opening
        # parenthesis.
        #
        # Example:
        #     printf(
        #            ^
        # -------------------------------------------------
        self.expect("IDENT", "printf")
        self.expect("PUNCT", "(")

        # -------------------------------------------------
        # The first argument must be a string literal.
        #
        # Example:
        #     printf("%d\n", x);
        #             ^^^^^
        #
        # The lexer has already decoded escape sequences
        # such as \n and \t.
        # -------------------------------------------------
        format_value = self.expect("STRING").value

        format_string = StringLiteral(
            value=format_value
        )

        # Store additional arguments in a list.
        arguments = []

        # -------------------------------------------------
        # Parse optional additional arguments.
        #
        # Each argument is a complete expression.
        #
        # Examples:
        #     x
        #     x + y
        #     (x * 2)
        #
        # The comma separates arguments. It is not part
        # of the expression itself.
        # -------------------------------------------------
        while (
            self.current().kind == "PUNCT"
            and self.current().value == ","
        ):
            # Consume the comma.
            self.advance()

            # Parse the next argument expression.
            arguments.append(
                self.parse_expression()
            )

        # Closing parenthesis.
        self.expect("PUNCT", ")")

        # Every printf statement ends with a semicolon.
        self.expect("PUNCT", ";")

        # Construct the Print AST node.
        return Print(
            format_string=format_string,
            arguments=arguments,
        )

    def parse_return_statement(self):
        """
        Grammar:
            return_statement := "return" expression ";"
        """

        self.expect("KEYWORD", "return")

        # Read the integer token.
        #token = self.expect("INT")
         # Parse a complete expression.
        value = self.parse_expression()

        # Convert its textual representation into a number.
        #value = self.parse_integer(token)

        # Every return statement must end with a semicolon.
        self.expect("PUNCT", ";")

        # Construct the AST nodes.
        return Return(value=value)

    def parse_variable_declaration(self):
        """
        Grammar:
            variable_declaration := "int" IDENT ("," IDENT)* ";"

        Examples:
            int x;
            int x, y, z;
        """

        var_type = self.expect("KEYWORD", "int").value

        names = []

        # First variable is mandatory.
        names.append(self.expect("IDENT").value)

        # Additional variables are optional.
        while (
            self.current().kind == "PUNCT"
            and self.current().value == ","
        ):
            self.advance()
            names.append(self.expect("IDENT").value)

        self.expect("PUNCT", ";")

        return VariableDeclaration(
            var_type=var_type,
            names=names,
        )


    def parse_primary(self):
        """
        Parse a primary expression.

        Grammar:
            primary := INT
                     | IDENT
                     | "(" expression ")"

        Primary expressions are the basic building blocks
        of larger expressions.

        Examples:
            42
            x
            (x + y)

        Integer literals become IntLiteral AST nodes.
        Variable names become Variable AST nodes.
        Parentheses contain another complete expression.
        """

        # Examine the current token without consuming it.
        token = self.current()

        # -------------------------------------------------
        # Integer literal
        #
        # Example:
        #     42
        #
        # Convert the token's textual representation into
        # a Python integer and create an IntLiteral node.
        # -------------------------------------------------
        if token.kind == "INT":
            self.advance()

            return IntLiteral(
                value=self.parse_integer(token)
            )

        # -------------------------------------------------
        # Variable reference
        #
        # Example:
        #     x
        #
        # At this stage we only record the variable name.
        # Later semantic analysis will check whether the
        # variable has actually been declared.
        # -------------------------------------------------
        if token.kind == "IDENT":
            self.advance()

            return Variable(
                name=token.value
            )

        # -------------------------------------------------
        # Parenthesized expression
        #
        # Example:
        #     (x + y) * 2
        #
        # Parentheses override normal operator precedence.
        # Parse the expression inside them recursively.
        # -------------------------------------------------
        if token.kind == "PUNCT" and token.value == "(":
            self.advance()

            expression = self.parse_expression()

            # A closing parenthesis must follow the expression.
            self.expect("PUNCT", ")")

            return expression

        # -------------------------------------------------
        # No valid primary expression was found.
        #
        # Report the exact source position to help identify
        # the syntax error.
        # -------------------------------------------------
        raise ParserError(
            f"{token.line}:{token.column}: expected expression, "
            f"got {token.value!r}"
        )

    def get_precedence(self, operator):
        """
        Return the precedence level of a binary operator.

        Higher values bind more tightly.

        Comparison operators have lower precedence than
        arithmetic operators.

        Example:
            x + 2 < y * 3

        Is interpreted as:
            (x + 2) < (y * 3)
        """

        precedence = {
            # Comparison operators
            "<": 5,
            ">": 5,
            "<=": 5,
            ">=": 5,
            "==": 5,
            "!=": 5,

            # Addition and subtraction
            "+": 10,
            "-": 10,

            # Multiplication, division and modulo
            "*": 20,
            "/": 20,
            "%": 20,
        }

        return precedence.get(operator, -1)

        
    def parse_assignment(self):
        """
        Parse a variable assignment statement.

        Grammar:
            assignment := IDENT "=" expression ";"

        Examples:
            x = 10;
            y = x + 5;
            z = (x + y) * 2;

        The expression on the right-hand side may contain
        literals, variables, operators and parentheses.

        Note:
            This initial implementation supports simple
            assignments only. It does not yet support
            compound assignments such as += or -=.
        """

        # -------------------------------------------------
        # Read the destination variable name.
        #
        # Example:
        #     x = 10;
        #     ^
        # -------------------------------------------------
        name = self.expect("IDENT").value

        # Assignment operator.
        self.expect("OP", "=")

        # -------------------------------------------------
        # Parse the complete right-hand-side expression.
        #
        # This is important: we do not simply read one
        # token after "=".
        #
        # For example:
        #     z = x + y * 2;
        #
        # parse_expression() builds the entire expression
        # tree, respecting operator precedence.
        # -------------------------------------------------
        value = self.parse_expression()

        # Every assignment statement must end with ';'.
        self.expect("PUNCT", ";")

        # Create an Assignment AST node.
        return Assignment(
            name=name,
            value=value,
        )

    def parse_expression(self, min_precedence=0):
        """
        Parse a binary expression using precedence climbing.

        Grammar conceptually:
            expression := primary (operator expression)*

        The minimum precedence argument controls which
        operators are allowed to be consumed at this level.

        Example:
            x + y * 2

        Parsing process:

            1. Read x as the initial left expression.
            2. Encounter + (precedence 10).
            3. Parse the right side with minimum precedence 11.
            4. Encounter y, followed by * (precedence 20).
            5. Since 20 >= 11, multiplication is parsed first.
            6. Construct x + (y * 2).

        This produces the correct operator precedence
        without requiring a separate parser method for
        every precedence level.
        """

        # -------------------------------------------------
        # Start by parsing the leftmost primary expression.
        #
        # It may be an integer, variable or parenthesized
        # expression.
        # -------------------------------------------------
        left = self.parse_primary()

        # -------------------------------------------------
        # Continue while the next token is a supported
        # binary operator with sufficient precedence.
        # -------------------------------------------------
        while True:

            token = self.current()

            # Only operator tokens can continue a binary
            # expression.
            if token.kind != "OP":
                break

            # Determine how strongly this operator binds.
            precedence = self.get_precedence(token.value)

            # If the operator has lower precedence than
            # the current parsing level, leave it for the
            # caller to process.
            if precedence < min_precedence:
                break

            # Consume the operator.
            operator = self.advance().value

            # -------------------------------------------------
            # Parse the right-hand side recursively.
            #
            # Adding 1 to the precedence makes operators
            # of equal precedence associate to the left.
            #
            # For example:
            #     10 - 5 - 2
            #
            # Becomes:
            #     (10 - 5) - 2
            # -------------------------------------------------
            right = self.parse_expression(precedence + 1)

            # -------------------------------------------------
            # Combine the left and right expressions into
            # a new BinaryExpression AST node.
            #
            # The resulting expression becomes the new
            # left side for the next iteration.
            # -------------------------------------------------
            left = BinaryExpression(
                left=left,
                operator=operator,
                right=right,
            )

        # Return the complete expression tree.
        return left

    def parse_while_statement(self):
        """
        Parse a while loop.

        Grammar:
            while_statement := "while" "(" expression ")" block

        Example:
            while (x < 10) {
                x = x + 1;
            }

        The condition is evaluated before every iteration.
        If it is false initially, the body is never executed.
        """

        # Consume the while keyword.
        self.expect("KEYWORD", "while")

        # Opening parenthesis.
        self.expect("PUNCT", "(")

        # Parse the loop condition.
        condition = self.parse_expression()

        # Closing parenthesis.
        self.expect("PUNCT", ")")

        # Parse the loop body.
        body = self.parse_block()

        # Construct the While AST node.
        return While(
            condition=condition,
            body=body,
        )

    def parse_do_while_statement(self):
        """
        Parse a do-while loop.

        Grammar:
            do_while_statement :=
                "do" block "while" "(" expression ")" ";"

        Example:
            do {
                x = x + 1;
            } while (x < 10);

        Unlike a normal while loop, the body executes
        before the condition is evaluated.

        Therefore, it always executes at least once.
        """

        # Consume the do keyword.
        self.expect("KEYWORD", "do")

        # Parse the loop body.
        body = self.parse_block()

        # The while keyword follows the closing brace.
        self.expect("KEYWORD", "while")

        # Opening parenthesis.
        self.expect("PUNCT", "(")

        # Parse the condition.
        condition = self.parse_expression()

        # Closing parenthesis.
        self.expect("PUNCT", ")")

        # A do-while statement ends with a semicolon.
        self.expect("PUNCT", ";")

        # Construct the DoWhile AST node.
        return DoWhile(
            body=body,
            condition=condition,
        )

