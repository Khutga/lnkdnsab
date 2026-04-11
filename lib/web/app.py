from flask import Flask, request, jsonify, send_from_directory
import traceback
import json
import time
import os

app = Flask(__name__, static_folder='.', static_url_path='')

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,tr;q=0.8',
}

try:
    import requests as http_req
    REQ_OK = True
    REQ_ERR = ''
except Exception as e:
    REQ_OK = False
    REQ_ERR = str(e)

try:
    from bs4 import BeautifulSoup
    BS4_OK = True
    BS4_ERR = ''
except Exception as e:
    BS4_OK = False
    BS4_ERR = str(e)


@app.route('/')
def index():
    return send_from_directory('.', 'cv-analyzer.html')


@app.route('/api/health')
def health():
    return jsonify({
        'status': 'ok',
        'requests_ok': REQ_OK,
        'requests_err': REQ_ERR,
        'bs4_ok': BS4_OK,
        'bs4_err': BS4_ERR,
    })


@app.route('/api/search', methods=['POST'])
def api_search():
    try:
        if not REQ_OK or not BS4_OK:
            return jsonify({'error': f'Missing: requests={REQ_ERR} bs4={BS4_ERR}'}), 500

        data = request.json or {}
        query = data.get('query', '')
        location = data.get('location', '')
        max_results = min(data.get('max_results', 25), 50)

        if not query:
            return jsonify({'error': 'query required'}), 400

        jobs = []
        seen = set()
        url = f'https://www.linkedin.com/jobs/search?keywords={http_req.utils.quote(query)}&location={http_req.utils.quote(location)}&start=0'
        resp = http_req.get(url, headers=HEADERS, timeout=20)

        if resp.status_code != 200:
            return jsonify({'error': f'LinkedIn {resp.status_code}', 'jobs': [], 'count': 0})

        soup = BeautifulSoup(resp.text, 'html.parser')
        cards = soup.select('div.base-card, li.result-card, div.job-search-card')

        for card in cards:
            if len(jobs) >= max_results:
                break
            title_el = card.select_one('h3, h4, a.base-card__full-link')
            link_el = card.select_one('a[href*="/jobs/view/"]')
            company_el = card.select_one('h4.base-search-card__subtitle, a.hidden-nested-link')
            loc_el = card.select_one('span.job-search-card__location')
            job_url = ''
            if link_el and link_el.get('href'):
                job_url = link_el['href'].split('?')[0]
            if not job_url or job_url in seen:
                continue
            seen.add(job_url)
            jobs.append({
                'title': title_el.get_text(strip=True) if title_el else '?',
                'company': company_el.get_text(strip=True) if company_el else '?',
                'location': loc_el.get_text(strip=True) if loc_el else '',
                'url': job_url,
            })

        return jsonify({'jobs': jobs, 'count': len(jobs)})
    except Exception as e:
        return jsonify({'error': str(e), 'trace': traceback.format_exc()}), 500


@app.route('/api/scrape', methods=['POST'])
def api_scrape():
    try:
        data = request.json or {}
        url = data.get('url', '')
        if not url:
            return jsonify({'error': 'url required'}), 400
        resp = http_req.get(url, headers=HEADERS, timeout=20)
        soup = BeautifulSoup(resp.text, 'html.parser')
        desc_el = soup.select_one('div.description__text, div.show-more-less-html__markup, section.show-more-less-html')
        return jsonify({'description': desc_el.get_text(separator='\n', strip=True) if desc_el else ''})
    except Exception as e:
        return jsonify({'description': '', 'error': str(e)}), 500


@app.route('/api/groq', methods=['POST'])
def api_groq():
    try:
        data = request.json or {}
        api_key = data.get('api_key', '')
        prompt = data.get('prompt', '')
        json_mode = data.get('json_mode', True)

        if not api_key or not prompt:
            return jsonify({'error': 'api_key and prompt required'}), 400

        body = {
            'model': 'llama-3.3-70b-versatile',
            'messages': [{'role': 'user', 'content': prompt}],
            'temperature': 0.3,
        }
        if json_mode:
            body['response_format'] = {'type': 'json_object'}
        else:
            body['max_tokens'] = 2000

        models = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant']

        for model in models:
            body['model'] = model
            resp = http_req.post(
                'https://api.groq.com/openai/v1/chat/completions',
                headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {api_key}'},
                json=body,
                timeout=90
            )
            if resp.status_code == 429:
                continue
            return jsonify(resp.json())

        return jsonify({'error': 'Tüm modellerin limiti dolmuş. 20dk bekleyin.'}), 429
    except Exception as e:
        return jsonify({'error': str(e), 'trace': traceback.format_exc()}), 500


if __name__ == '__main__':
    app.run(port=5000, debug=True)