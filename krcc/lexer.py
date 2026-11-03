
from dataclasses import dataclass


# A token is the smallest meaningful unit of source code.
# For example, "int", "main", "42", and ";" are tokens.
@dataclass(frozen=True)
class Token:
    kind: str       # Token category: KEYWORD, IDENT, INT, PUNCT, or EOF
    value: str      # Original text, such as "return" or "42"
    line: int       # Source line number, used in error messages
    column: int     # Column number, used in error messages


# Words with special meaning in our initial subset of C.
# Other names, such as "main", are ordinary identifiers.

KEYWORDS = {
    "int",
    "void",
    "return",
    "while",
    "do",
}

# Operators
OPERATORS = {
    "+", "-", "*", "/", "%",
    "=", "<", ">", "!",
    "==", "!=", "<=", ">=",
    "&&", "||",
}


# Punctuation recognized by the first version of the lexer.
# We will add operators such as +, -, and = when needed.
PUNCTUATION = set("(){};,")


# A dedicated exception makes lexical errors easy to distinguish
# from parser errors and other compiler failures.
class LexerError(Exception):
    pass


class Lexer:
    def __init__(self, source: str):
        # The complete C source file as a string.
        self.source = source

        # Current character offset into the source string.
        self.pos = 0

        # Human-readable position, starting at line 1, column 1.
        self.line = 1
        self.column = 1

    def peek(self):
        # Look at the current character without consuming it.
        # An empty string means we have reached the end of the source.
        if self.pos >= len(self.source):
            return ""
        return self.source[self.pos]

    def advance(self):
        # Consume one character and update the source position.
        ch = self.peek()

        if not ch:
            return ""

        self.pos += 1

        # A newline starts a new line; other characters advance
        # the column number.
        if ch == "\n":
            self.line += 1
            self.column = 1
        else:
            self.column += 1

        return ch

    def tokenize(self):
        # Convert the source into a list of tokens.
        # The parser will consume this list in the next compiler stage.
        tokens = []

        while self.peek():
            ch = self.peek()

            # Whitespace separates tokens but has no meaning here.
            if ch.isspace():
                self.advance()
                continue

            # Remember where this token starts so errors can point
            # to the original location in the source file.
            line, column = self.line, self.column

            # -------------------------------------------------
            # Line comment: // comment
            # Skip characters up to, but not including, newline.
            # The main loop will consume the newline as whitespace.
            # -------------------------------------------------
            if self.source.startswith("//", self.pos):
                while self.peek() and self.peek() != "\n":
                    self.advance()
                continue

            # -------------------------------------------------
            # Block comment: /* comment */
            # Consume the opening delimiter, scan to the closing
            # delimiter, and report an error if it is missing.
            # -------------------------------------------------
            if self.source.startswith("/*", self.pos):
                self.advance()  # Consume /
                self.advance()  # Consume *

                while self.peek() and not self.source.startswith(
                    "*/", self.pos
                ):
                    self.advance()

                if not self.peek():
                    raise LexerError(
                        f"{line}:{column}: unterminated block comment"
                    )

                self.advance()  # Consume *
                self.advance()  # Consume /
                continue

            # -------------------------------------------------
            # Identifier or keyword
            #
            # Examples:
            #   int       -> KEYWORD
            #   return    -> KEYWORD
            #   main      -> IDENT
            #   counter   -> IDENT
            #
            # Identifiers start with a letter or underscore.
            # Subsequent characters may also contain digits.
            # -------------------------------------------------
            if ch.isalpha() or ch == "_":
                start = self.pos

                while self.peek() and (
                    self.peek().isalnum() or self.peek() == "_"
                ):
                    self.advance()

                # Extract the complete word from the source.
                value = self.source[start:self.pos]

                # A recognized keyword has a different token kind
                # from a user-defined name.
                kind = "KEYWORD" if value in KEYWORDS else "IDENT"

                tokens.append(Token(kind, value, line, column))
                continue

            # -------------------------------------------------
            # Integer literal
            #
            # Initially supports decimal numbers (42) and
            # hexadecimal numbers (0x2A).
            # The token stores the original spelling; conversion
            # to a numeric value happens later in the parser.
            # -------------------------------------------------
            if ch.isdigit():
                start = self.pos

                if self.source.startswith(("0x", "0X"), self.pos):
                    # Consume the 0x prefix.
                    self.advance()
                    self.advance()

                    digit_start = self.pos

                    # Consume hexadecimal digits.
                    while self.peek() and self.peek() in (
                        "0123456789abcdefABCDEF"
                    ):
                        self.advance()

                    # A prefix without any hexadecimal digits is invalid.
                    if self.pos == digit_start:
                        raise LexerError(
                            f"{line}:{column}: invalid hexadecimal integer"
                        )
                else:
                    # Consume decimal digits.
                    while self.peek() and self.peek().isdigit():
                        self.advance()

                value = self.source[start:self.pos]
                tokens.append(Token("INT", value, line, column))
                continue

            if ch == '"':
                self.advance()
                value = []
                escapes = {
                    '"': '"',
                    "\\": "\\",
                    "n": "\n",
                    "r": "\r",
                    "t": "\t",
                }

                while self.peek() and self.peek() != '"':
                    if self.peek() == "\n":
                        raise LexerError(
                            f"{line}:{column}: unterminated string literal"
                        )
                    if self.peek() == "\\":
                        self.advance()
                        escaped = self.peek()
                        if escaped not in escapes:
                            raise LexerError(
                                f"{self.line}:{self.column}: "
                                f"unsupported string escape \\{escaped}"
                            )
                        value.append(escapes[escaped])
                        self.advance()
                    else:
                        value.append(self.advance())

                if self.peek() != '"':
                    raise LexerError(
                        f"{line}:{column}: unterminated string literal"
                    )

                self.advance()
                tokens.append(Token("STRING", "".join(value), line, column))
                continue

            # -------------------------------------------------
            # Operators
            # Check two-character operators first (longest match).
            # -------------------------------------------------
            matched = False

            for op in sorted(OPERATORS, key=len, reverse=True):
                if self.source.startswith(op, self.pos):
                    tokens.append(Token("OP", op, line, column))

                    for _ in op:
                        self.advance()

                    matched = True
                    break

            if matched:
                continue

            # -------------------------------------------------
            # Punctuation
            #
            # Examples: ( ) { } ; ,
            # Each character becomes its own token.
            # -------------------------------------------------
            if ch in PUNCTUATION:
                tokens.append(Token("PUNCT", ch, line, column))
                self.advance()
                continue

            # Any character not recognized by the current language
            # subset is an error rather than silently ignored.
            raise LexerError(
                f"{line}:{column}: unexpected character {ch!r}"
            )

        # An explicit end-of-file token lets the parser detect
        # when it has consumed the entire program.
        tokens.append(Token("EOF", "", self.line, self.column))

        return tokens
