"""
BMM RNG Demo Web Application
For BMM audit demonstration - provides web UI to test RNG functionality
"""

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import hashlib
import os

# Import BMM_RNG module (will be uploaded during audit)
try:
    from BMM_RNG import (
        make_rng, RNGInfo,
        draw_gems, draw_gems_named,
        egypt_hilo_play_once,
        forest_tea_party_play_once,
        lucky_drop_coco2_play_once,
        MultiHiloSession, MultiHiloBet
    )
    RNG_LOADED = True
except ImportError:
    RNG_LOADED = False

app = FastAPI(
    title="BMM RNG Demo",
    description="BMM-Compliant RNG Demonstration Interface",
    version="1.0.0"
)

# ----------------------- Models -----------------------

class RNGRequest(BaseModel):
    mode: str = "system"  # "system" or "deterministic"
    seed_hex: Optional[str] = None
    context: Optional[str] = None

class GemDrawRequest(RNGRequest):
    n_draws: int = 5

class EgyptHiloRequest(RNGRequest):
    pass

class ForestTeaPartyRequest(RNGRequest):
    step: int = 10
    target_rtp: float = 0.93

class LuckyDropRequest(RNGRequest):
    bet_amount: float = 1.0
    jackpot_pool: float = 0.0

class MultiHiloRequest(RNGRequest):
    bet_type: str = "Red"
    params: Optional[Dict[str, Any]] = None

# ----------------------- API Endpoints -----------------------

@app.get("/api/status")
def get_status():
    """Check if BMM_RNG.py is loaded and get its checksum"""
    result = {
        "rng_loaded": RNG_LOADED,
        "rng_file_exists": os.path.exists("BMM_RNG.py"),
        "checksum": None
    }

    if os.path.exists("BMM_RNG.py"):
        with open("BMM_RNG.py", "rb") as f:
            result["checksum"] = hashlib.sha256(f.read()).hexdigest()

    return result

@app.post("/api/gems/draw")
def draw_gems_api(req: GemDrawRequest):
    """Draw gems using RNG"""
    if not RNG_LOADED:
        raise HTTPException(status_code=503, detail="BMM_RNG.py not loaded")

    rng, info = make_rng(
        mode=req.mode,
        seed_hex=req.seed_hex,
        context=req.context or "GemGame-Demo"
    )

    indices = draw_gems(rng, n_draws=req.n_draws)
    names = draw_gems_named(rng, n_draws=req.n_draws)

    return {
        "rng_info": info.__dict__,
        "gem_indices": indices,
        "gem_names": names
    }

@app.post("/api/egypt-hilo/play")
def egypt_hilo_api(req: EgyptHiloRequest):
    """Play one round of Egypt Hilo"""
    if not RNG_LOADED:
        raise HTTPException(status_code=503, detail="BMM_RNG.py not loaded")

    rng, info = make_rng(
        mode=req.mode,
        seed_hex=req.seed_hex,
        context=req.context or "EgyptHilo-Demo"
    )

    result = egypt_hilo_play_once(rng)

    return {
        "rng_info": info.__dict__,
        "result": result
    }

@app.post("/api/forest-tea-party/play")
def forest_tea_party_api(req: ForestTeaPartyRequest):
    """Play one round of Forest Tea Party"""
    if not RNG_LOADED:
        raise HTTPException(status_code=503, detail="BMM_RNG.py not loaded")

    rng, info = make_rng(
        mode=req.mode,
        seed_hex=req.seed_hex,
        context=req.context or "ForestTeaParty-Demo"
    )

    result = forest_tea_party_play_once(rng, step=req.step, target_rtp=req.target_rtp)

    return {
        "rng_info": info.__dict__,
        "result": result
    }

@app.post("/api/lucky-drop/play")
def lucky_drop_api(req: LuckyDropRequest):
    """Play one round of Lucky Drop COCO2"""
    if not RNG_LOADED:
        raise HTTPException(status_code=503, detail="BMM_RNG.py not loaded")

    rng, info = make_rng(
        mode=req.mode,
        seed_hex=req.seed_hex,
        context=req.context or "LuckyDrop-Demo"
    )

    result = lucky_drop_coco2_play_once(
        rng,
        bet_amount=req.bet_amount,
        jackpot_pool=req.jackpot_pool
    )

    return {
        "rng_info": info.__dict__,
        "result": result
    }

@app.post("/api/multi-hilo/play")
def multi_hilo_api(req: MultiHiloRequest):
    """Play one round of Multi Hilo"""
    if not RNG_LOADED:
        raise HTTPException(status_code=503, detail="BMM_RNG.py not loaded")

    rng, info = make_rng(
        mode=req.mode,
        seed_hex=req.seed_hex,
        context=req.context or "MultiHilo-Demo"
    )

    session = MultiHiloSession(rng)

    bet_map = {
        "Red": MultiHiloBet.RED,
        "Black": MultiHiloBet.BLACK,
        "ExactRank": MultiHiloBet.EXACT_RANK,
        "Range_2_10": MultiHiloBet.RANGE_2_10,
        "Range_JQKA": MultiHiloBet.RANGE_JQKA,
        "Range_KA": MultiHiloBet.RANGE_KA,
        "HI": MultiHiloBet.HI,
        "LO": MultiHiloBet.LO,
        "Joker": MultiHiloBet.JOKER
    }

    bet = bet_map.get(req.bet_type, MultiHiloBet.RED)
    result = session.resolve_bet(bet, req.params)

    return {
        "rng_info": info.__dict__,
        "result": result
    }

# ----------------------- Web UI -----------------------

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RNG GAME</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        header {
            text-align: center;
            padding: 30px 0;
            border-bottom: 1px solid #333;
            margin-bottom: 30px;
        }
        header h1 { font-size: 2.5em; color: #00d4ff; }
        header p { color: #888; margin-top: 10px; }

        .status-bar {
            background: #0f3460;
            padding: 15px 20px;
            border-radius: 10px;
            margin-bottom: 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 10px;
        }
        .status-item { display: flex; align-items: center; gap: 8px; }
        .status-dot {
            width: 12px; height: 12px;
            border-radius: 50%;
            background: #ff4757;
        }
        .status-dot.ok { background: #2ed573; }
        .checksum {
            font-family: monospace;
            font-size: 0.85em;
            color: #ffd700;
            word-break: break-all;
        }

        .games-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
        }
        .game-card {
            background: #0f3460;
            border-radius: 15px;
            padding: 25px;
            border: 1px solid #1a1a4e;
        }
        .game-card h2 {
            color: #00d4ff;
            margin-bottom: 15px;
            font-size: 1.3em;
        }
        .game-card p {
            color: #888;
            font-size: 0.9em;
            margin-bottom: 20px;
        }

        .form-group {
            margin-bottom: 15px;
        }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            color: #aaa;
            font-size: 0.9em;
        }
        .form-group select, .form-group input {
            width: 100%;
            padding: 10px;
            border: 1px solid #333;
            border-radius: 8px;
            background: #1a1a2e;
            color: #fff;
            font-size: 1em;
        }
        .form-group input::placeholder { color: #555; }

        .btn {
            width: 100%;
            padding: 12px;
            border: none;
            border-radius: 8px;
            font-size: 1em;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s;
        }
        .btn-primary {
            background: linear-gradient(135deg, #00d4ff, #0066ff);
            color: #fff;
        }
        .btn-primary:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(0,212,255,0.4); }
        .btn-primary:disabled { background: #333; cursor: not-allowed; transform: none; }

        .result-box {
            margin-top: 20px;
            padding: 15px;
            background: #1a1a2e;
            border-radius: 10px;
            font-family: monospace;
            font-size: 0.85em;
            white-space: pre-wrap;
            word-break: break-all;
            max-height: 300px;
            overflow-y: auto;
            display: none;
        }
        .result-box.show { display: block; }
        .result-box .success { color: #2ed573; }
        .result-box .error { color: #ff4757; }

        .rng-mode-toggle {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
        }
        .rng-mode-toggle button {
            flex: 1;
            padding: 10px;
            border: 2px solid #333;
            border-radius: 8px;
            background: transparent;
            color: #888;
            cursor: pointer;
            transition: all 0.3s;
        }
        .rng-mode-toggle button.active {
            border-color: #00d4ff;
            color: #00d4ff;
            background: rgba(0,212,255,0.1);
        }
        .seed-input { display: none; }
        .seed-input.show { display: block; }

        footer {
            text-align: center;
            padding: 30px 0;
            margin-top: 40px;
            border-top: 1px solid #333;
            color: #555;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>RNG GAME</h1>
                    </header>

        <div class="status-bar">
            <div class="status-item">
                <span class="status-dot" id="statusDot"></span>
                <span id="statusText">Checking...</span>
            </div>
            <div class="status-item">
                <span>SHA256:</span>
                <span class="checksum" id="checksumDisplay">Loading...</span>
            </div>
        </div>

        <div class="games-grid">
            <!-- Gem Game -->
            <div class="game-card">
                <h2>🎰 Gem Game</h2>
                <p>Draw 5 gems from 7 colors using unbiased RNG</p>
                <div class="rng-mode-toggle">
                    <button class="active" onclick="setMode(this, 'gems', 'system')">System RNG</button>
                    <button onclick="setMode(this, 'gems', 'deterministic')">Deterministic</button>
                </div>
                <div class="seed-input" id="gems-seed">
                    <div class="form-group">
                        <label>Seed (Hex)</label>
                        <input type="text" id="gems-seed-input" placeholder="64 hex characters...">
                    </div>
                </div>
                <button class="btn btn-primary" onclick="playGems()">Draw Gems</button>
                <div class="result-box" id="gems-result"></div>
            </div>

            <!-- Egypt Hilo -->
            <div class="game-card">
                <h2>🏺 Egypt Hilo</h2>
                <p>Hi-Lo card game with cat collection and bonus</p>
                <div class="rng-mode-toggle">
                    <button class="active" onclick="setMode(this, 'egypt', 'system')">System RNG</button>
                    <button onclick="setMode(this, 'egypt', 'deterministic')">Deterministic</button>
                </div>
                <div class="seed-input" id="egypt-seed">
                    <div class="form-group">
                        <label>Seed (Hex)</label>
                        <input type="text" id="egypt-seed-input" placeholder="64 hex characters...">
                    </div>
                </div>
                <button class="btn btn-primary" onclick="playEgypt()">Play Round</button>
                <div class="result-box" id="egypt-result"></div>
            </div>

            <!-- Forest Tea Party -->
            <div class="game-card">
                <h2>🌲 Forest Tea Party</h2>
                <p>Multiplier-based game with configurable steps</p>
                <div class="rng-mode-toggle">
                    <button class="active" onclick="setMode(this, 'forest', 'system')">System RNG</button>
                    <button onclick="setMode(this, 'forest', 'deterministic')">Deterministic</button>
                </div>
                <div class="seed-input" id="forest-seed">
                    <div class="form-group">
                        <label>Seed (Hex)</label>
                        <input type="text" id="forest-seed-input" placeholder="64 hex characters...">
                    </div>
                </div>
                <div class="form-group">
                    <label>Steps</label>
                    <select id="forest-steps">
                        <option value="5">5 Steps</option>
                        <option value="10" selected>10 Steps</option>
                        <option value="15">15 Steps</option>
                        <option value="20">20 Steps</option>
                    </select>
                </div>
                <button class="btn btn-primary" onclick="playForest()">Play Round</button>
                <div class="result-box" id="forest-result"></div>
            </div>

            <!-- Lucky Drop -->
            <div class="game-card">
                <h2>🎯 Lucky Drop COCO2</h2>
                <p>Drop game with jackpot pool mechanics</p>
                <div class="rng-mode-toggle">
                    <button class="active" onclick="setMode(this, 'lucky', 'system')">System RNG</button>
                    <button onclick="setMode(this, 'lucky', 'deterministic')">Deterministic</button>
                </div>
                <div class="seed-input" id="lucky-seed">
                    <div class="form-group">
                        <label>Seed (Hex)</label>
                        <input type="text" id="lucky-seed-input" placeholder="64 hex characters...">
                    </div>
                </div>
                <div class="form-group">
                    <label>Bet Amount</label>
                    <input type="number" id="lucky-bet" value="1.0" min="0.1" step="0.1">
                </div>
                <button class="btn btn-primary" onclick="playLucky()">Play Round</button>
                <div class="result-box" id="lucky-result"></div>
            </div>

            <!-- Multi Hilo -->
            <div class="game-card">
                <h2>🃏 Multi Hilo</h2>
                <p>54-card Hi-Lo with multiple bet types</p>
                <div class="rng-mode-toggle">
                    <button class="active" onclick="setMode(this, 'hilo', 'system')">System RNG</button>
                    <button onclick="setMode(this, 'hilo', 'deterministic')">Deterministic</button>
                </div>
                <div class="seed-input" id="hilo-seed">
                    <div class="form-group">
                        <label>Seed (Hex)</label>
                        <input type="text" id="hilo-seed-input" placeholder="64 hex characters...">
                    </div>
                </div>
                <div class="form-group">
                    <label>Bet Type</label>
                    <select id="hilo-bet">
                        <option value="Red">Red</option>
                        <option value="Black">Black</option>
                        <option value="HI">HI</option>
                        <option value="LO">LO</option>
                        <option value="Range_2_10">Range 2-10</option>
                        <option value="Range_JQKA">Range J-Q-K-A</option>
                        <option value="Range_KA">Range K-A</option>
                        <option value="Joker">Joker</option>
                    </select>
                </div>
                <button class="btn btn-primary" onclick="playHilo()">Play Round</button>
                <div class="result-box" id="hilo-result"></div>
            </div>
        </div>

        <footer>
                    </footer>
    </div>

    <script>
        const gameModes = {
            gems: 'system',
            egypt: 'system',
            forest: 'system',
            lucky: 'system',
            hilo: 'system'
        };

        function setMode(btn, game, mode) {
            gameModes[game] = mode;
            btn.parentElement.querySelectorAll('button').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            const seedDiv = document.getElementById(game + '-seed');
            if (mode === 'deterministic') {
                seedDiv.classList.add('show');
            } else {
                seedDiv.classList.remove('show');
            }
        }

        function getRequestBody(game) {
            const body = { mode: gameModes[game] };
            if (gameModes[game] === 'deterministic') {
                const seedInput = document.getElementById(game + '-seed-input');
                if (seedInput && seedInput.value) {
                    body.seed_hex = seedInput.value;
                } else {
                    body.seed_hex = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
                }
            }
            return body;
        }

        function showResult(elementId, data, isError = false) {
            const el = document.getElementById(elementId);
            el.classList.add('show');
            el.innerHTML = `<span class="${isError ? 'error' : 'success'}">${JSON.stringify(data, null, 2)}</span>`;
        }

        async function checkStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();

                const dot = document.getElementById('statusDot');
                const text = document.getElementById('statusText');
                const checksum = document.getElementById('checksumDisplay');

                if (data.rng_loaded) {
                    dot.classList.add('ok');
                    text.textContent = 'RNG Loaded';
                    checksum.textContent = data.checksum || 'N/A';
                } else {
                    dot.classList.remove('ok');
                    text.textContent = 'RNG Not Loaded';
                    checksum.textContent = 'File not found';
                }
            } catch (e) {
                console.error('Status check failed:', e);
            }
        }

        async function playGems() {
            try {
                const body = getRequestBody('gems');
                body.n_draws = 5;
                const res = await fetch('/api/gems/draw', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(body)
                });
                const data = await res.json();
                showResult('gems-result', data, !res.ok);
            } catch (e) {
                showResult('gems-result', {error: e.message}, true);
            }
        }

        async function playEgypt() {
            try {
                const body = getRequestBody('egypt');
                const res = await fetch('/api/egypt-hilo/play', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(body)
                });
                const data = await res.json();
                showResult('egypt-result', data, !res.ok);
            } catch (e) {
                showResult('egypt-result', {error: e.message}, true);
            }
        }

        async function playForest() {
            try {
                const body = getRequestBody('forest');
                body.step = parseInt(document.getElementById('forest-steps').value);
                const res = await fetch('/api/forest-tea-party/play', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(body)
                });
                const data = await res.json();
                showResult('forest-result', data, !res.ok);
            } catch (e) {
                showResult('forest-result', {error: e.message}, true);
            }
        }

        async function playLucky() {
            try {
                const body = getRequestBody('lucky');
                body.bet_amount = parseFloat(document.getElementById('lucky-bet').value);
                const res = await fetch('/api/lucky-drop/play', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(body)
                });
                const data = await res.json();
                showResult('lucky-result', data, !res.ok);
            } catch (e) {
                showResult('lucky-result', {error: e.message}, true);
            }
        }

        async function playHilo() {
            try {
                const body = getRequestBody('hilo');
                body.bet_type = document.getElementById('hilo-bet').value;
                const res = await fetch('/api/multi-hilo/play', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(body)
                });
                const data = await res.json();
                showResult('hilo-result', data, !res.ok);
            } catch (e) {
                showResult('hilo-result', {error: e.message}, true);
            }
        }

        // Check status on load
        checkStatus();
        setInterval(checkStatus, 10000);
    </script>
</body>
</html>
"""

@app.get("/", response_class=HTMLResponse)
async def home():
    return HTML_TEMPLATE

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
