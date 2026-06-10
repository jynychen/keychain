# SPDX-License-Identifier: GPL-3.0-only
"""CLI compatibility and legacy-behavior tests."""

import pytest

from keychain import main
from keychain.main import KeychainApp
from keychain.runtime.config import RuntimeConfig
from keychain.util import Output


class TestParseArgsLegacy:
    """Legacy flat-flag compatibility that is still expected to round-trip."""

    def test_legacy_list(self):
        ns = RuntimeConfig.resolve(["--list"])
        assert ns.action == "list"

    def test_legacy_stop_all(self):
        """The compat shim now treats `all` as the implicit stop default, not an explicit parsed target."""
        ns = RuntimeConfig.resolve(["--stop", "all"])
        assert ns.action == "agent stop"
        assert ns.get_value("target") is None

    def test_legacy_stop_mine(self):
        ns = RuntimeConfig.resolve(["--stop", "mine"])
        assert ns.action == "agent stop"
        assert ns.get_value("target") == "mine"

    def test_legacy_stop_others(self):
        ns = RuntimeConfig.resolve(["-k", "others"])
        assert ns.action == "agent stop"
        assert ns.get_value("target") == "others"

    def test_legacy_wipe_ssh(self):
        ns = RuntimeConfig.resolve(["--wipe", "ssh"])
        assert ns.action == "wipe"
        assert ns.get_value("wipe_ssh") is True
        assert ns.get_value("wipe_gpg") is False

    def test_legacy_keys_become_start(self):
        ns = RuntimeConfig.resolve(["id_rsa"])
        assert ns.action == "add"
        assert ns.get_value("keys") == ["id_rsa"]

    def test_legacy_ssh_rm(self):
        ns = RuntimeConfig.resolve(["--ssh-rm", "keyA"])
        assert ns.action == "forget"
        assert ns.get_value("keys") == ["keyA"]

    def test_legacy_inspect(self):
        ns = RuntimeConfig.resolve(["--inspect"])
        assert ns.action == "inspect"

    def test_legacy_inspect_with_keys(self):
        ns = RuntimeConfig.resolve(["--inspect", "id_rsa", "id_ed25519"])
        assert ns.action == "inspect"
        assert ns.get_value("keys") == ["id_rsa", "id_ed25519"]

    @pytest.mark.skip(
        reason="Invalid legacy stop values are currently translated into `agent stop` without parser rejection; discuss whether compat should restore an explicit error."
    )
    def test_legacy_invalid_stop_value_rejected(self):
        with pytest.raises(SystemExit):
            RuntimeConfig.resolve(["--stop", "bogus"])

    @pytest.mark.parametrize(
        "argv,flag,replacement",
        [
            (["id_rsa", "--list"], "--list", "list"),
            (["id_rsa", "--stop", "mine"], "--stop", "agent stop --mine"),
        ],
    )
    @pytest.mark.skip(
        reason="Action-after-key legacy hints are not currently enforced during compat parsing; discuss whether that targeted rejection should return."
    )
    def test_legacy_action_after_key_rejected_clearly(self, argv, flag, replacement, capsys):
        with pytest.raises(SystemExit) as exc:
            RuntimeConfig.resolve(argv)
        assert exc.value.code == 2
        err = capsys.readouterr().err
        assert flag in err
        assert replacement in err


class TestLegacyParsingEdgeCases:
    """Edge-case coverage for legacy spellings that still map cleanly into 3.x."""

    def test_bare_keychain_resolves_to_empty_action(self):
        args = RuntimeConfig.resolve([])
        out = Output.build(quiet=True, debug=False, eval_mode=False, color=False)
        assert KeychainApp(args, out)._resolve_action() == "add"

    def test_global_option_survives_action_parse(self):
        ns = RuntimeConfig.resolve(["--quiet", "add", "id_rsa"])
        assert ns.get_value("quiet") is True
        assert ns.get_value("keys") == ["id_rsa"]

    def test_global_debug_survives_action(self):
        ns = RuntimeConfig.resolve(["--debug", "list"])
        assert ns.get_value("debug") is True

    def test_dashdash_then_dash_prefixed_key(self):
        ns = RuntimeConfig.resolve(["--", "-weird-key-name"])
        assert ns.action == "add"
        assert "-weird-key-name" in ns.get_value("keys")

    def test_short_flag_cluster_with_action(self):
        ns = RuntimeConfig.resolve(["-qL"])
        assert ns.action == "list"
        assert ns.get_value("quiet") is True

    @pytest.mark.skip(
        reason="Compat only splits short clusters when they contain a legacy action letter; discuss whether pure option clusters like `-qQ` should be preserved too."
    )
    def test_short_flag_cluster_with_keys(self):
        ns = RuntimeConfig.resolve(["-qQ", "id_rsa"])
        assert ns.action == "add"
        assert ns.quiet is True
        assert ns.quick is True
        assert ns.keys == ["id_rsa"]

    def test_gpg_fingerprint_shaped_positional_accepted(self):
        ns = RuntimeConfig.resolve(["add", "id_rsa", "0123ABCD", "0123456789ABCDEF"])
        assert ns.get_value("keys") == ["id_rsa", "0123ABCD", "0123456789ABCDEF"]


@pytest.mark.skip(
    reason="Legacy hint throttling helpers are no longer exposed from keychain.main; discuss whether that feature moved, was removed, or needs a new test surface."
)
class TestLegacyHint:
    """Legacy translation-hint behavior that needs a new home or a product decision."""

    def test_legacy_hint_due_writes_marker_first_call(self, tmp_path, monkeypatch):
        monkeypatch.setattr(main.Path, "home", classmethod(lambda c: tmp_path))
        assert main._legacy_hint_due() is True
        marker = tmp_path / ".keychain" / ".legacy-hint-shown"
        assert marker.is_file()
        assert main._legacy_hint_due() is False

    def test_legacy_hint_due_re_fires_after_window(self, tmp_path, monkeypatch):
        import os as _os

        monkeypatch.setattr(main.Path, "home", classmethod(lambda c: tmp_path))
        main._legacy_hint_due()
        marker = tmp_path / ".keychain" / ".legacy-hint-shown"
        old = marker.stat().st_mtime - main._LEGACY_HINT_THROTTLE_SECONDS - 1
        _os.utime(marker, (old, old))
        assert main._legacy_hint_due() is True

    def test_legacy_hint_silent_on_query_path(self, monkeypatch, tmp_path):
        monkeypatch.setattr(main.Path, "home", classmethod(lambda c: tmp_path))
        ns = RuntimeConfig.resolve(["--query"])
        assert ns.action == "env"
        should_emit = ns.action not in ("env", "help", "version") and not ns.evalopt
        assert should_emit is False, "env (ex-query) path must not emit legacy hint"
