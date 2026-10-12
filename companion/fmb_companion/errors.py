"""Fixed public errors: never include native errors, identities or token values."""


class CompanionError(Exception):
    """Expose only an internal constant code to the CLI and its diagnostics."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)
