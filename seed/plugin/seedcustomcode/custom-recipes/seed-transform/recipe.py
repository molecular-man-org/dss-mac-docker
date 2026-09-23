# Seeded CustomCode recipe. Not intended to be run — it exists so that a
# CustomCode_* recipe type is present for inventory and language mapping.
import dataiku
from dataiku.customrecipe import get_input_names_for_role, get_output_names_for_role

src = dataiku.Dataset(get_input_names_for_role("input_ds")[0])
dst = dataiku.Dataset(get_output_names_for_role("output_ds")[0])
dst.write_schema(src.read_schema())
