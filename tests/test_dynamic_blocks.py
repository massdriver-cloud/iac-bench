"""closed_values reads the content of a dynamic block that always renders."""
from iacbench import checks

SPEC = {"type": "google_sql_database_instance", "attrs": {"settings.ip_configuration.ipv4_enabled": False}}

def module(tmp_path, for_each, value="false"):
    (tmp_path / "main.tf").write_text(f"""
variable "public" {{
  type    = bool
  default = false
}}

resource "google_sql_database_instance" "this" {{
  settings {{
    dynamic "ip_configuration" {{
      for_each = {for_each}
      content {{
        ipv4_enabled = {value}
      }}
    }}
  }}
}}
""")
    return checks._verb_closed_values(checks.CheckContext(module_dir=tmp_path, defaults_plan=None), SPEC)


def test_constant_for_each_is_read_like_a_static_block(tmp_path):
    assert module(tmp_path, "[1]") is True


def test_input_gated_dynamic_block_is_not_closed(tmp_path):
    assert module(tmp_path, "var.public ? [] : [1]") is False


def test_empty_literal_is_not_closed(tmp_path):
    assert module(tmp_path, "[]") is False


def test_open_value_inside_constant_block_still_fails(tmp_path):
    assert module(tmp_path, "[1]", value="var.public") is False
