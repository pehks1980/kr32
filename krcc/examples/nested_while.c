int main(void) {
    int x;
    int y;

    x = 0;
    y = 0;

    while (x < 3) {
        y = 0;

        while (y < 2) {
            y = y + 1;
        }

        x = x + 1;
    }

    return x + y;
}
