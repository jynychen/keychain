# This source file provides an API for accessing _doc_texts.json efficiently, with
# cached loading and parsing. The primary consumer of this API is the actions.py module,
# as the primary linkage should be from Option() and Action() objects to their corresponding
# doc text.

from __future__ import annotations

import json
from functools import cache
from importlib.resources import files


class DocText:
    @cache  # noqa: B019
    def _data(self) -> dict[str, dict[str, dict[str, str]]]:
        blob = files("keychain").joinpath("docs").joinpath("_doc_texts.json").read_text(encoding="utf-8")
        data = json.loads(blob)
        data.setdefault("option", {}).update(data.pop("global", {}))
        return data

    def _entry(self, doc_tag: str) -> dict[str, str]:
        section, _, key = doc_tag.partition(":")
        if not section or not key:
            return {}
        return self._data().get(section, {}).get(key, {})

    def short_help(self, doc_tag: str) -> str:
        return self._entry(doc_tag).get("short_help", "")

    def description(self, doc_tag: str) -> str:
        return self._entry(doc_tag).get("description", "")


DOC_TEXT = DocText()
