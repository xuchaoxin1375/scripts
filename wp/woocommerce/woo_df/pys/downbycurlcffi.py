from __future__ import annotations

import asyncio
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

from curl_cffi import requests

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
]

TIMEOUT = 20
MAX_CONCURRENCY = 80
RETRIES = 3


@dataclass
class DownloadResult:
    url: str
    output_path: str
    ok: bool
    status_code: Optional[int] = None
    error: Optional[str] = None


async def _write_bytes(output_path: str, content: bytes) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # 使用线程池避免磁盘写入阻塞事件循环。
    await asyncio.to_thread(path.write_bytes, content)


async def download_image(
    session: requests.AsyncSession,
    semaphore: asyncio.Semaphore,
    url: str,
    output_path: str,
    user_agent: str = USER_AGENTS[0],
    timeout: int = TIMEOUT,
    proxies=None,
    curl_insecure: bool = False,
    impersonate: str = "chrome",
    retries: int = RETRIES,
) -> DownloadResult:
    """
    下载单张图片。建议由 download_images_concurrent 统一调度调用。
    """
    last_error = None

    async with semaphore:
        for attempt in range(retries + 1):
            try:
                resp = await session.get(
                    url,
                    headers={"User-Agent": user_agent},
                    timeout=timeout,
                    proxies=proxies,
                    verify=not curl_insecure,
                    impersonate=impersonate,  # type: ignore
                )
                status_code = getattr(resp, "status_code", None)
                if status_code and status_code >= 400:
                    raise RuntimeError(f"HTTP {status_code}")

                await _write_bytes(output_path, resp.content)
                return DownloadResult(
                    url=url, output_path=output_path, ok=True, status_code=status_code
                )

            except Exception as exc:  # pylint: disable=broad-except
                last_error = exc
                if attempt < retries:
                    backoff = 0.35 * (2**attempt) + random.uniform(0, 0.25)
                    await asyncio.sleep(backoff)

    return DownloadResult(
        url=url,
        output_path=output_path,
        ok=False,
        error=str(last_error),
    )


async def download_images_concurrent(
    tasks: Sequence[tuple[str, str]],
    user_agent: str = USER_AGENTS[0],
    timeout: int = TIMEOUT,
    proxies=None,
    curl_insecure: bool = False,
    impersonate: str = "chrome",
    max_concurrency: int = MAX_CONCURRENCY,
    retries: int = RETRIES,
) -> list[DownloadResult]:
    """
    批量并发下载。

    参数:
      tasks: [(url, output_path), ...]
    """
    semaphore = asyncio.Semaphore(max_concurrency)

    # 单 Session 复用连接池，在高并发下效率明显更高。
    async with requests.AsyncSession() as session:
        coros = [
            download_image(
                session=session,
                semaphore=semaphore,
                url=url,
                output_path=output_path,
                user_agent=user_agent,
                timeout=timeout,
                proxies=proxies,
                curl_insecure=curl_insecure,
                impersonate=impersonate,
                retries=retries,
            )
            for url, output_path in tasks
        ]
        return list(await asyncio.gather(*coros))


def download_by_curl_cffi_async(
    tasks: Sequence[tuple[str, str]],
    user_agent: str = USER_AGENTS[0],
    timeout: int = TIMEOUT,
    proxies=None,
    curl_insecure: bool = False,
    impersonate: str = "chrome",
    max_concurrency: int = MAX_CONCURRENCY,
    retries: int = RETRIES,
) -> list[DownloadResult]:
    """
    同步入口，方便外部直接调用。
    """
    return asyncio.run(
        download_images_concurrent(
            tasks=tasks,
            user_agent=user_agent,
            timeout=timeout,
            proxies=proxies,
            curl_insecure=curl_insecure,
            impersonate=impersonate,
            max_concurrency=max_concurrency,
            retries=retries,
        )
    )


if __name__ == "__main__":
    demo_tasks = [
        ("https://picsum.photos/seed/a/1200/800", "downloads/a.jpg"),
        ("https://picsum.photos/seed/b/1200/800", "downloads/b.jpg"),
    ]
    results = download_by_curl_cffi_async(demo_tasks, max_concurrency=50)
    ok_count = sum(r.ok for r in results)
    print(f"done: {ok_count}/{len(results)}")
