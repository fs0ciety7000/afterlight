#!/usr/bin/env python3
"""Audio lot (2026-11-06, cap 5 USD, ledger art/source/LOT_2026-11-06_audio.md).

One billed fal call per item of art/source/audio/plan.json. Before each call the ledger row is written ("en cours")
and the call is refused if the running total would pass the cap. FAL_KEY comes from the environment (never printed).

  python3 tools/fal/audio.py list            # items, estimated cost, done or not
  python3 tools/fal/audio.py run <id>...     # generate items (one at a time)
  python3 tools/fal/audio.py run --all       # every item not generated yet
"""
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PLAN = os.path.join(ROOT, 'art/source/audio/plan.json')
RAW = os.path.join(ROOT, 'art/source/audio/raw')
LOG = os.path.join(ROOT, 'art/source/audio/fal_log.json')
LEDGER = os.path.join(ROOT, 'art/source/LOT_2026-11-06_audio.md')
CAP = 5.00
PRICE_STABLE = 0.20  # per audio
PRICE_ELEVEN = 0.002  # per second


def cost(item):
    if 'stable-audio' in item['model']:
        return PRICE_STABLE
    return round(PRICE_ELEVEN * item['seconds'], 4)


def fmt(v):
    return f'{v:.3f}'.replace('.', ',')


def ledger_rows():
    rows = []
    for line in open(LEDGER, encoding='utf-8'):
        m = re.match(r'^\| (\d+) \|', line)
        if m:
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            rows.append(cells)
    return rows


def spent():
    return round(sum(float(r[6].replace(',', '.')) for r in ledger_rows()), 4)


def write_row(n, endpoint, name, label, result, c, cum):
    row = f'| {n} | {time.strftime("%H:%M", time.gmtime())} UTC | {endpoint} | `{name}` | {label} | {result} | ' \
          f'{fmt(c)} | {fmt(cum)} |\n'
    text = open(LEDGER, encoding='utf-8').read()
    pat = re.compile(rf'^\| {n} \|.*\n', re.M)
    if pat.search(text):
        text = pat.sub(row, text)
    else:  # after the last row of the table (the ledger may go on below it)
        last = list(re.finditer(r'^\| \d+ \|.*\n', text, re.M))[-1]
        text = text[:last.end()] + row + text[last.end():]
    open(LEDGER, 'w', encoding='utf-8').write(text)


def urls_in(obj):
    if isinstance(obj, dict):
        if isinstance(obj.get('url'), str) and obj['url'].startswith('http'):
            return [obj['url']]
        return [u for v in obj.values() for u in urls_in(v)]
    if isinstance(obj, list):
        return [u for v in obj for u in urls_in(v)]
    return []


def run(item, plan):
    import fal_client

    c = cost(item)
    before = spent()
    if before + c > CAP:
        sys.exit(f'refused: {item["id"]} would bring the lot to {before + c:.3f} > {CAP}')
    n = len(ledger_rows()) + 1
    label = {'music': 'Musique', 'sting': 'Jingle', 'sfx': 'Effet', 'loop': 'Ambiance'}[item['kind']]
    write_row(n, item['model'], item['id'], label, 'en cours', c, before + c)
    if 'stable-audio' in item['model']:
        prompt = f'{item["prompt"]}. {plan["style_music"]}'
        args = {'prompt': prompt, 'seconds_total': item['seconds'], 'seed': item['seed'],
                'num_inference_steps': 8}
    else:
        prompt = item['prompt']
        args = {'text': prompt, 'duration_seconds': item['seconds'], 'prompt_influence': 0.5,
                'output_format': 'mp3_44100_128'}
        if item.get('loop'):
            args['loop'] = True
    t0 = time.time()
    try:
        result = fal_client.subscribe(item['model'], arguments=args, with_logs=False)
    except Exception as e:  # noqa: BLE001 - recorded in the ledger, then re-raised
        # Refused before running (balance, validation): not billed. Check the bill if it failed later.
        write_row(n, item['model'], item['id'], label, f'refusé ou échec, non facturé : {str(e)[:50]}', 0.0, before)
        raise
    os.makedirs(RAW, exist_ok=True)
    files = []
    for i, url in enumerate(urls_in(result)):
        ext = os.path.splitext(url.split('?')[0])[1] or '.bin'
        dest = os.path.join(RAW, item['id'] + ('' if i == 0 else f'_{i}') + ext)
        urllib.request.urlretrieve(url, dest)
        files.append(os.path.relpath(dest, ROOT))
    write_row(n, item['model'], item['id'], label, 'OK' if files else 'aucun fichier', c, before + c)
    log = json.load(open(LOG)) if os.path.exists(LOG) else []
    log.append({'id': item['id'], 'endpoint': item['model'], 'prompt': prompt,
                'arguments': {k: v for k, v in args.items() if k not in ('prompt', 'text')},
                'seed': args.get('seed'), 'duration_s': item['seconds'], 'cost_usd': c,
                'seconds': round(time.time() - t0, 1), 'files': files,
                'result_seed': result.get('seed') if isinstance(result, dict) else None})
    with open(LOG, 'w') as f:
        json.dump(log, f, indent=1, ensure_ascii=False)
    print(item['id'], files, f'cum {before + c:.3f}')


def main():
    plan = json.load(open(PLAN))
    items = {i['id']: i for i in plan['items']}
    done = {e['id'] for e in (json.load(open(LOG)) if os.path.exists(LOG) else [])}
    if len(sys.argv) < 2 or sys.argv[1] == 'list':
        for i in plan['items']:
            print(f'{i["id"]:24} {cost(i):.3f} {"done" if i["id"] in done else ""}')
        print('estimate', round(sum(cost(i) for i in plan['items']), 3), 'spent', spent())
        return
    if not os.environ.get('FAL_KEY'):
        sys.exit('FAL_KEY is not set')
    ids = [i for i in items if i not in done] if sys.argv[2:] == ['--all'] else sys.argv[2:]
    for i in ids:
        run(items[i], plan)


if __name__ == '__main__':
    main()
