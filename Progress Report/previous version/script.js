// 1. Data Structure with Detailed Progress (Pedagogical Breakdown)
const milestonesData = [
    {
        date: "August 2026",
        title: "Laying the Foundation",
        description: "We set up the basic skeleton of the project—a fast backend to process data and a mobile app to display it.",
        tags: ["System Architecture", "Flutter Setup", "FastAPI Init"],
        details: {
            challenge: "Traffic enforcement systems require handling massive amounts of video data in real-time. If the foundation isn't built correctly, the entire system will crash under load.",
            solution: "We initialized a high-speed Python backend (FastAPI) to act as the brain, and a cross-platform mobile app (Flutter) so enforcers can access the system from any phone or tablet.",
            impact: "This created a highly scalable blank canvas, allowing us to build and plug in complex AI models later without breaking the core system.",
            codeUpdated: "main.py, pubspec.yaml",
            snippet: `from fastapi import FastAPI\n\napp = FastAPI(title="Huli-Kamote API")\n\n@app.get("/")\ndef read_root():\n    return {"status": "System Online"}`,
            graph: `graph TD;\n    A[Camera Feed] --> B(FastAPI Backend);\n    B --> C[(Database)];\n    C --> D[Flutter Mobile App];\n    C --> E[Web Dashboard];`
        }
    },
    {
        date: "Early September 2026",
        title: "Bridging the Knowledge Gap",
        description: "We built interactive visualizers to explain exactly how the AI decides a violation has occurred.",
        tags: ["Educational UI", "Math Breakdown", "Transparency"],
        details: {
            challenge: "AI often acts like a 'black box.' It's hard for professors, users, or drivers to trust the system if they don't understand how it detects violations like Illegal Parking.",
            solution: "We created a 4-Phase interactive educational tool. It visually breaks down the geometry and math, showing the evolution from simple 'Brute Force' detection to 'Modern AI Tracking.'",
            impact: "Users can now visually see the exact rules the AI uses. This makes the system transparent, trustworthy, and highly educational for academic purposes.",
            codeUpdated: "lib/visualizers/, main_screen.dart",
            snippet: `// Example of phase state management for education\nenum ViolationPhase {\n  phase0_BruteForce,\n  phase1_MathConcept,\n  phase2_RealWorldSetup,\n  phase3_ModernAI\n}`,
            graph: `graph LR;\n    A[Violation Scenario] --> B[Phase 0: Old Way];\n    B --> C[Phase 1: Math Concept];\n    C --> D[Phase 2: Real World];\n    D --> E[Phase 3: Modern AI];`
        }
    },
    {
        date: "Mid September 2026",
        title: "Supercharging the AI Engine",
        description: "We broke the monolithic code into smaller pieces and unlocked hardware acceleration to process video faster.",
        tags: ["Hardware GPU", "Decoupling", "Speed Optimization"],
        details: {
            challenge: "Processing heavy video frames through multiple AI models simultaneously was causing extreme lag and low frames-per-second (FPS).",
            solution: "We decoupled the system into a 'Cascading Pipeline' (processing one task at a time) and forced the AI to run directly on the graphics card (GPU) instead of the CPU.",
            impact: "The system achieved a 300% boost in processing speed. It can now monitor traffic in real-time without freezing or dropping frames.",
            codeUpdated: "pipeline.py, registry.py, track_ledger.py",
            snippet: `def _initialize_gpu():\n    # Force the AI to use the Graphics Card for extreme speed\n    providers = [\n        ('CUDAExecutionProvider', {'device_id': 0}),\n        'CPUExecutionProvider' # Fallback only\n    ]\n    return ort.InferenceSession(model_path, providers=providers)`,
            graph: `graph TD;\n    V[Video Feed] --> C[Primary AI: Find Vehicles];\n    C --> B[Slicer: Crop Vehicles];\n    B --> D[Tracker: Follow Vehicles];\n    D --> S1[Helmet AI];\n    D --> S2[License Plate AI];`
        }
    },
    {
        date: "Late September 2026",
        title: "Human-Assisted AI Verification",
        description: "We built a dashboard for human enforcers to review AI tickets and correct mistakes, which organically trains the AI.",
        tags: ["Forensics", "Human-in-Loop", "Smart OCR"],
        details: {
            challenge: "No AI is 100% perfect. Blurry license plates, extreme weather, or strange angles can cause the AI to generate false tickets.",
            solution: "We introduced an 'Inbox' where enforcers verify tickets. If the AI makes a mistake, the enforcer corrects it (Pop-Quiz ML). We also added AI upscaling (Real-ESRGAN) to clarify blurry plates.",
            impact: "The system now learns from human corrections, getting smarter every day while ensuring innocent drivers aren't falsely penalized.",
            codeUpdated: "forensic_analyzer_screen.dart, store.py",
            snippet: `def deduplicate_tickets(new_ticket, existing_tickets):\n    # Group tickets if the license plate is off by just 1 letter\n    for t in existing_tickets:\n        if levenshtein_distance(new_ticket.plate, t.plate) <= 1:\n            t.merge_evidence(new_ticket)\n            return t\n    return new_ticket`,
            graph: `graph TD;\n    A[AI Generates Ticket] --> B[Enforcer Inbox];\n    B --> C{Is Ticket Correct?};\n    C -- Yes --> D[Approve & Send Fine];\n    C -- No --> E[Enforcer Corrects Data];\n    E --> F[AI Retrains & Learns];`
        }
    },
    {
        date: "Early October 2026",
        title: "Mastering Complex Traffic Rules",
        description: "We taught the AI to understand complex, moving behavioral violations like Swerving and Red Light running.",
        tags: ["Behavioral Rules", "Track Stitching", "Spatial Logic"],
        details: {
            challenge: "Detecting a missing helmet is easy because it's static. But detecting 'swerving' or a 'red light violation' requires the AI to track an object's behavior over time and space.",
            solution: "We built custom 'Track Stitching' logic to remember vehicles even if they get temporarily blocked by a tree. We then added spatial evaluators to monitor lanes and traffic lights.",
            impact: "The framework is no longer just an object detector. It can now enforce dynamic, behavioral traffic laws, making it a complete enforcement solution.",
            codeUpdated: "train.py, track_stitcher.py, traffic_light.py",
            snippet: `def merge_lost_tracks(new_track, lost_tracks):\n    # Re-link a car if the AI temporarily lost sight of it\n    for lt in lost_tracks:\n        if is_match(new_track.color, lt.color) and time_gap < 2_seconds:\n            new_track.id = lt.id\n            return`,
            graph: `graph LR;\n    A[Car passes behind tree] --> B[AI loses tracking ID];\n    B --> C[Car reappears];\n    C --> D{Does color/size match?};\n    D -- Yes --> E[Stitch ID back together];\n    E --> F[Continuous tracking];`
        }
    },
    {
        date: "Current (October 2026)",
        title: "Preparing for the Real World",
        description: "We are polishing the system's ability to monitor specific, custom-drawn zones on a road.",
        tags: ["Custom Zones", "Real-World Setup", "Benchmarking"],
        details: {
            challenge: "Every intersection is different. The AI needs to know exactly where the 'illegal parking' zone is versus the 'driving' lane.",
            solution: "We implemented a Multi-Zone Configuration. Enforcers can draw custom polygons directly on the video feed to define rules for specific areas of the road.",
            impact: "The system is now fully customizable for any road layout in the real world, ready for final stress testing and benchmarking.",
            codeUpdated: "camera_config.json, training.py, pipeline.py",
            snippet: `{\n  "illegal_parking": {\n    "rois": [\n      {\n        "polygon": [[26, 1060], [1882, 1068], [1363, 394], [491, 426]]\n      }\n    ],\n    "time_limit": 180.0\n  }\n}`,
            graph: `graph TD;\n    A[Enforcer Draws Polygon] --> B[Save Camera Config];\n    B --> C[AI Video Pipeline];\n    C --> D{Is car inside Polygon?};\n    D -- Yes --> E[Start Violation Timer];\n    D -- No --> F[Ignore Car];`
        }
    }
];

// Expose globally for inline onclick
window.openModalWrapper = function(index) {
    if (milestonesData[index]) {
        openModal(milestonesData[index]);
    }
};

// 2. Render Milestones to DOM
function renderMilestones() {
    const container = document.getElementById('timeline-container');
    
    milestonesData.forEach((milestone, index) => {
        const alignmentClass = index % 2 === 1 ? 'right' : '';
        const tagsHtml = milestone.tags.map(tag => `<li>${tag}</li>`).join('');

        const section = document.createElement('section');
        section.className = `milestone ${alignmentClass}`;
        
        section.innerHTML = `
            <div class="milestone-dot"></div>
            <!-- INLINE ONCLICK FOR BULLETPROOF REGISTRATION -->
            <div class="card 3d-card" data-index="${index}" onclick="window.openModalWrapper(${index})" style="cursor: pointer; position: relative; z-index: 10;">
                <div class="card-glow" style="pointer-events: none;"></div>
                <div class="card-content" style="pointer-events: none;">
                    <span class="date">${milestone.date}</span>
                    <h2>${milestone.title}</h2>
                    <p>${milestone.description}</p>
                    <ul class="tags">
                        ${tagsHtml}
                    </ul>
                </div>
            </div>
        `;
        
        container.appendChild(section);
    });
}

// 3. Initialize Animations & Interactivity
function initAnimations() {
    // Scroll Animations
    const milestones = document.querySelectorAll('.milestone');
    const observerOptions = { root: null, rootMargin: '0px', threshold: 0.3 };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('active');
            }
        });
    }, observerOptions);

    milestones.forEach(milestone => observer.observe(milestone));

    // 3D Card Hover Effect
    const cards = document.querySelectorAll('.3d-card');
    cards.forEach(card => {
        const glow = card.querySelector('.card-glow');

        card.addEventListener('mousemove', (e) => {
            if (window.getComputedStyle(card).opacity < 0.9) return;
            const rect = card.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;

            glow.style.left = `${x}px`;
            glow.style.top = `${y}px`;

            const centerX = rect.width / 2;
            const centerY = rect.height / 2;
            
            const rotateX = ((y - centerY) / centerY) * -5;
            const rotateY = ((x - centerX) / centerX) * 5;

            card.style.transition = 'transform 0.1s ease, box-shadow 0.1s ease';
            card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(1.02, 1.02, 1.02)`;
        });

        card.addEventListener('mouseleave', () => {
            card.style.transition = 'transform 0.8s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.8s ease';
            card.style.transform = 'perspective(1000px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)';
        });
    });
}

// 4. Modal Logic (Pedagogical UI)
function openModal(data) {
    const modalOverlay = document.getElementById('modal-overlay');
    const modalContent = document.getElementById('modal-content');
    
    // Inject HTML content with Challenge -> Solution -> Impact flow
    modalContent.innerHTML = `
        <div class="modal-header">
            <span class="modal-date">${data.date}</span>
            <h2>${data.title}</h2>
        </div>
        
        <div class="modal-section" style="background: rgba(255, 69, 58, 0.1); padding: 20px; border-left: 4px solid #ff453a; border-radius: 8px;">
            <h3 style="color: #ff453a; margin-top: 0;">The Challenge</h3>
            <p style="color: #eee; margin-bottom: 0;">${data.details.challenge}</p>
        </div>

        <div class="modal-section" style="background: rgba(48, 209, 88, 0.1); padding: 20px; border-left: 4px solid #30d158; border-radius: 8px;">
            <h3 style="color: #30d158; margin-top: 0;">What We Built (Solution)</h3>
            <p style="color: #eee; margin-bottom: 0;">${data.details.solution}</p>
        </div>

        <div class="modal-section" style="background: rgba(10, 132, 255, 0.1); padding: 20px; border-left: 4px solid #0a84ff; border-radius: 8px;">
            <h3 style="color: #0a84ff; margin-top: 0;">The Impact</h3>
            <p style="color: #eee; margin-bottom: 0;">${data.details.impact}</p>
        </div>

        <div class="modal-section">
            <h3>Visual Flowchart</h3>
            <div class="graph-box">
                <div class="mermaid">
                    ${data.details.graph}
                </div>
            </div>
        </div>

        <div class="modal-section">
            <h3>Under the Hood (Core Files)</h3>
            <p style="font-family: monospace; color: #fff; background: rgba(255,255,255,0.1); padding: 5px 10px; border-radius: 6px; display: inline-block;">${data.details.codeUpdated}</p>
        </div>

        <div class="modal-section">
            <h3>Code Snippet</h3>
            <pre><code class="language-python">${data.details.snippet}</code></pre>
        </div>
    `;

    // Show modal
    modalOverlay.classList.add('active');
    
    // Render Mermaid Graph safely
    try {
        if (typeof mermaid !== 'undefined') {
            if (mermaid.run) {
                mermaid.run({ querySelector: '.mermaid' });
            } else {
                mermaid.init(undefined, document.querySelectorAll('.mermaid'));
            }
        }
    } catch (err) {
        console.warn("Mermaid rendering failed", err);
    }
    
    // Render Highlight.js safely
    try {
        if (typeof hljs !== 'undefined') {
            document.querySelectorAll('pre code').forEach((block) => {
                hljs.highlightElement(block);
            });
        }
    } catch (err) {
        console.warn("HighlightJS rendering failed", err);
    }
}

document.getElementById('modal-close').addEventListener('click', () => {
    document.getElementById('modal-overlay').classList.remove('active');
});

// Close modal on click outside
document.getElementById('modal-overlay').addEventListener('click', (e) => {
    if (e.target.id === 'modal-overlay') {
        document.getElementById('modal-overlay').classList.remove('active');
    }
});

// 5. Three.js Background
function initThreeJS() {
    const canvas = document.querySelector('#bg-canvas');
    if (typeof THREE !== 'undefined') {
        const scene = new THREE.Scene();
        const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
        camera.position.z = 30;

        const renderer = new THREE.WebGLRenderer({ canvas: canvas, alpha: true, antialias: true });
        renderer.setPixelRatio(window.devicePixelRatio);
        renderer.setSize(window.innerWidth, window.innerHeight);

        const geometry = new THREE.BufferGeometry();
        const particlesCount = 700;
        const posArray = new Float32Array(particlesCount * 3);

        for(let i = 0; i < particlesCount * 3; i++) {
            posArray[i] = (Math.random() - 0.5) * 100;
        }

        geometry.setAttribute('position', new THREE.BufferAttribute(posArray, 3));

        const material = new THREE.PointsMaterial({
            size: 0.05,
            color: 0x007aff,
            transparent: true,
            opacity: 0.4,
            blending: THREE.AdditiveBlending
        });

        const particlesMesh = new THREE.Points(geometry, material);
        scene.add(particlesMesh);

        let mouseX = 0;
        let mouseY = 0;
        
        document.addEventListener('mousemove', (event) => {
            mouseX = event.clientX / window.innerWidth - 0.5;
            mouseY = event.clientY / window.innerHeight - 0.5;
        });

        let scrollY = window.scrollY;
        window.addEventListener('scroll', () => {
            scrollY = window.scrollY;
        });

        const clock = new THREE.Clock();

        function animate() {
            requestAnimationFrame(animate);
            const elapsedTime = clock.getElapsedTime();

            particlesMesh.rotation.y = elapsedTime * 0.05;
            particlesMesh.rotation.x += mouseY * 0.05;
            particlesMesh.rotation.y += mouseX * 0.05;

            camera.position.y = -scrollY * 0.01;
            renderer.render(scene, camera);
        }
        animate();

        window.addEventListener('resize', () => {
            camera.aspect = window.innerWidth / window.innerHeight;
            camera.updateProjectionMatrix();
            renderer.setSize(window.innerWidth, window.innerHeight);
        });
    }
}

// Boot up the application
document.addEventListener('DOMContentLoaded', () => {
    // Initialize Mermaid configuration safely
    try {
        if (typeof mermaid !== 'undefined') {
            mermaid.initialize({ startOnLoad: false, theme: 'dark' });
        }
    } catch (e) {
        console.warn("Mermaid initialize skipped", e);
    }
    
    renderMilestones();
    initAnimations();
    initThreeJS();
});
