import os

# Chip deposit in EUR (e.g. 3.0 for 3 Euro).
# Configured via CHIP_DEPOSIT in config.env.
# Applied automatically on first chip issuance; refunded automatically on payout.
# Set to 0 to disable deposit logic entirely.
CHIP_DEPOSIT: float = float(os.getenv("CHIP_DEPOSIT", "0"))
