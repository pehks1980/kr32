int multiply_and_add(int value)
{
    return (2 + 3) * (4 + 5) + value;
}


int main(void)
{
    int result;
    result = multiply_and_add(10);

    printf("Result: %d\n", result); // Output: Result: 55

    return result;
}