
from dataclasses import fields, is_dataclass


def print_ast(node, indent=0, label=None):
    prefix = " " * indent

    if label:
        print(f"{prefix}{label}:")

    prefix = " " * (indent + 2)

    if is_dataclass(node):
        print(f"{prefix}{type(node).__name__}")

        for field in fields(node):
            value = getattr(node, field.name)

            if isinstance(value, list):
                print(f"{prefix}  {field.name}:")

                for item in value:
                    print_ast(item, indent + 4)

            elif is_dataclass(value):
                print_ast(value, indent + 2, field.name)

            else:
                print(f"{prefix}  {field.name}: {value}")

    else:
        print(f"{prefix}{node}")
