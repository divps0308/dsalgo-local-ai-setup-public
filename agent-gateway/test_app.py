import base64

import pytest
from fastapi import HTTPException

from app import normalize_messages_for_ollama, parse_compatibility_tool_calls


def test_normalize_text_and_image_blocks():
    encoded = base64.b64encode(b"fake-image").decode("ascii")
    result = normalize_messages_for_ollama([{
        "role": "user",
        "content": [
            {"type": "text", "text": "What is this?"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encoded}"}},
        ],
    }])
    assert result[0]["content"] == "What is this?"
    assert result[0]["images"] == [encoded]


def test_normalize_preserves_text_only_messages():
    message = {"role": "user", "content": "hello", "name": "tester"}
    assert normalize_messages_for_ollama([message]) == [message]


@pytest.mark.parametrize("url", ["https://example.com/image.png", "data:image/png,not-base64"])
def test_rejects_remote_or_invalid_images(url):
    with pytest.raises(HTTPException) as error:
        normalize_messages_for_ollama([{"role": "user", "content": [{"type": "image_url", "image_url": {"url": url}}]}])
    assert error.value.status_code == 400


def test_rejects_unsupported_content_block():
    with pytest.raises(HTTPException) as error:
        normalize_messages_for_ollama([{"role": "user", "content": [{"type": "audio", "data": "..."}]}])
    assert error.value.status_code == 400


def test_normalize_text_document_attachment():
    encoded = base64.b64encode("line one\nline two".encode()).decode()
    result = normalize_messages_for_ollama([{"role": "user", "content": [
        {"type": "text", "text": "Summarize this"},
        {"type": "file", "file_data": f"data:text/plain;base64,{encoded}"},
    ]}])
    assert "line one" in result[0]["content"]
    assert "[End attached document]" in result[0]["content"]


def test_rejects_remote_document_url():
    with pytest.raises(HTTPException) as error:
        normalize_messages_for_ollama([{"role": "user", "content": [{"type": "file", "file_url": {"url": "https://example.com/a.pdf"}}]}])
    assert error.value.status_code == 400


def test_recovers_explicit_tool_code_call():
    calls = parse_compatibility_tool_calls('''I will fetch it now.\n```tool_code\nhttp_get("https://example.com")\n```''', {"http_get"})
    assert calls == [{"function": {"name": "http_get", "arguments": {"url": "https://example.com"}}}]


def test_recovers_json_tool_call_and_deduplicates():
    text = '{"name":"get_datetime","arguments":{}}\n```tool_code\nget_datetime({})\n```'
    calls = parse_compatibility_tool_calls(text, {"get_datetime"})
    assert calls == [{"function": {"name": "get_datetime", "arguments": {}}}]


def test_recovers_keyword_argument_tool_call():
    calls = parse_compatibility_tool_calls('```tool_code\nhttp_get(url="https://example.com", max_chars=100)\n```', {"http_get"})
    assert calls == [{"function": {"name": "http_get", "arguments": {"url": "https://example.com", "max_chars": 100}}}]


def test_does_not_execute_unallowlisted_or_ambiguous_text():
    assert parse_compatibility_tool_calls('I cannot access the internet.', {"http_get"}) == []
    assert parse_compatibility_tool_calls('```tool_code\nrun_command("whoami")\n```', {"http_get"}) == []
