"""Generate a simple alarm .wav file for the Smart Helmet app."""
import wave
import struct
import math

SAMPLE_RATE = 44100
DURATION = 3.0  # seconds
FREQ_HIGH = 880.0  # Hz — shrill alarm tone
FREQ_LOW = 440.0   # Hz — alternating lower tone
AMPLITUDE = 0.6

n_samples = int(SAMPLE_RATE * DURATION)
frames = []

for i in range(n_samples):
    t = i / SAMPLE_RATE
    # Alternate between high and low tone every 0.25s for alarm effect
    freq = FREQ_HIGH if (t % 0.5) < 0.25 else FREQ_LOW
    # Fade in first 50ms to avoid click
    env = min(t * 20, 1.0) if t < 0.05 else 1.0
    sample = int(AMPLITUDE * env * 32767 * math.sin(2 * math.pi * freq * t))
    frames.append(struct.pack('<h', sample))

out_path = r'd:\IOT\SmartHelmet\firmware_test\flutter_app\assets\sounds\alarm.wav'
with wave.open(out_path, 'w') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(SAMPLE_RATE)
    wf.writeframes(b''.join(frames))

print(f'Generated: {out_path}')
print(f'Duration: {DURATION}s, Freq: {FREQ_HIGH}/{FREQ_LOW}Hz, Sample rate: {SAMPLE_RATE}Hz')
