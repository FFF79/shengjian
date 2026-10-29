#!/usr/bin/env python3
"""Search thematic notes or independent raw transcripts using the Obsidian JSONL indexes."""
import argparse, json, sys
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('query')
    parser.add_argument('--root', required=True, type=Path, help='Obsidian vault root')
    parser.add_argument('--raw-root', type=Path, help='Explicit shared raw transcript directory on this device')
    parser.add_argument('--subject')
    parser.add_argument('--mode', choices=['study', 'other'])
    parser.add_argument('--context')
    parser.add_argument('--unclassified', action='store_true')
    parser.add_argument('--source', choices=['notes', 'raw', 'all'], default='notes')
    parser.add_argument('--limit', type=int, default=12)
    args = parser.parse_args()
    tokens = args.query.casefold().split()
    if not tokens: parser.error('query must contain text')
    if args.limit < 1: parser.error('limit must be positive')
    root = args.root.resolve()
    def inside(relative):
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or Path(relative).is_absolute(): raise ValueError('Index path outside vault')
        return path
    def rows(path):
        return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    catalog = inside('_声笺/agent/catalog.jsonl')
    records = inside('_声笺/agent/records')
    entries = {row['id']: row for row in rows(catalog)} if catalog.is_file() else {}
    if records.is_dir():
        for manifest in records.glob('*.json'):
            if manifest.is_symlink(): continue
            row = json.loads(manifest.read_text()); entries[row['id']] = row
    if not entries: parser.error('No note indexes found')
    if args.subject: entries = {key: row for key, row in entries.items() if row['subject'] == args.subject}
    if args.mode: entries = {key: row for key, row in entries.items() if row.get('mode', 'study') == args.mode}
    if args.context: entries = {key: row for key, row in entries.items() if row.get('context') == args.context}
    if args.unclassified: entries = {key: row for key, row in entries.items() if row.get('needsClassification')}
    hits = []
    if args.source in ['notes', 'all']:
        aggregate = inside('_声笺/agent/sections.jsonl')
        sections = {row['section_id']: row for row in rows(aggregate)} if aggregate.is_file() else {}
        for entry in entries.values():
            individual = inside(entry.get('sectionIndexPath', '_声笺/agent/sections.jsonl'))
            if individual != aggregate and individual.is_file():
                sections = {key: row for key, row in sections.items() if row['recording_id'] != entry['id']}
                sections.update({row['section_id']: row for row in rows(individual)})
        for section in sections.values():
            entry = entries.get(section['recording_id'])
            if not entry: continue
            text = section.get('text', '')
            score = sum(text.casefold().count(token) + 3 * section['heading'].casefold().count(token) for token in tokens)
            if score:
                hits.append({'source': 'note', 'score': score, 'title': entry['title'], 'subject': entry['subject'],
                    'mode': entry.get('mode', 'study'), 'context': entry.get('context'),
                    'needs_classification': entry.get('needsClassification', False),
                    'created_at': entry['createdAt'], 'section_id': section['section_id'], 'heading': section['heading'],
                    'note_path': str(inside(entry['notePath'])), 'raw_path': entry['rawPath'],
                    'source_segment_ids': section.get('source_segment_ids', []), 'text': text})
    if args.source in ['raw', 'all']:
        for entry in entries.values():
            chunks = Path(entry['chunksPath'])
            if not chunks.is_absolute() or chunks.name != entry['id'] + '.jsonl': raise ValueError('Invalid external transcript index path')
            raw_path = entry['rawPath']
            if not chunks.is_file() and args.raw_root:
                chunks = args.raw_root / '.声笺/chunks' / (entry['id'] + '.jsonl')
                filename = entry.get('rawFileName')
                if filename and Path(filename).name == filename: raw_path = str(args.raw_root / filename)
            if not chunks.is_file():
                print(f'Raw transcript is not available on this device: {entry["id"]}', file=sys.stderr)
                continue
            for line in chunks.read_text().splitlines():
                if not line.strip(): continue
                chunk = json.loads(line)
                text = chunk.get('text', '')
                score = sum(text.casefold().count(token) for token in tokens)
                if score:
                    hits.append({'source': 'raw', 'score': score, 'title': entry['title'], 'subject': entry['subject'],
                        'created_at': entry['createdAt'], 'raw_path': raw_path, 'note_path': str(args.root / entry['notePath']),
                        'start_seconds': chunk['start_seconds'], 'end_seconds': chunk['end_seconds'],
                        'anchor': chunk['anchor'], 'text': text, 'transcript_complete': entry['transcriptComplete']})
    hits.sort(key=lambda row: (-row['score'], row['created_at']))
    for hit in hits[:args.limit]: print(json.dumps(hit, ensure_ascii=False))

if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError) as error:
        print(f'Search failed: {error}', file=sys.stderr); sys.exit(1)
