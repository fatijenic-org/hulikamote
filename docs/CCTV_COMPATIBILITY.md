# CCTV compatibility: what we claim, and what backs it

## The claim (for the defense)

> We do not claim that HULI-KAMOTE works on a real barangay CCTV. We surveyed the ways a CCTV system usually hands out
> its picture, and built the Live Monitor to accept those inputs. Only the camera address changes. What we tested is
> listed below, and what we did not test is stated just as plainly.

## How CCTV hands out its picture (research)

| Setup | What it looks like | Source | Our Live Monitor |
|---|---|---|---|
| **RTSP**, the standard way network cameras and recorders (DVR/NVR) stream | `rtsp://user:pass@192.168.1.20:554/path` | RTSP is an IETF standard: [RFC 7826](https://www.rfc-editor.org/rfc/rfc7826.html) (RTSP 2.0, obsoletes RFC 2326); it lets the client choose UDP, multicast or TCP delivery | Accepted (`rtsp://`, `rtsps://`). Uses TCP transport, 5 s open and read timeouts, reconnects by itself after 1, 2, 4, 8 s |
| **ONVIF cameras** (vendor-neutral standard) | The camera offers a stream address; a client reads it over RTSP | [ONVIF Profile S](https://www.onvif.org/profiles/profile-s/) covers live video over RTSP; [ONVIF Profile feature overview](https://www.onvif.org/wp-content/uploads/2019/12/ONVIF_Profile_Feature_overview_v2-3.pdf); [IPVM review](https://ipvm.com/reports/1182) | Works if you give it the camera's RTSP address. **Automatic ONVIF discovery is not built** |
| **Hikvision** DVR/NVR/cameras | `/Streaming/Channels/101` (channel 1 main), `102` (channel 1 sub), `1701` (channel 17 main) | [Hikvision support: RTSP format for NVR/DVR](https://supportusa.hikvision.com/support/solutions/articles/17000129024-do-you-have-an-example-showing-the-format-for-getting-a-rtsp-stream-from-a-nvr-dvr-); [list of RTSP URLs](https://www.smartrtsp.com/guides/rtsp-url-list) | Same as RTSP: paste the address |
| **Dahua** DVR/NVR/cameras | `/cam/realmonitor?channel=1&subtype=0` (0 main, 1 sub) | [Dahua RTSP format](https://securitycamcenter.com/rtsp-url-address-format-dahua/); [list of RTSP URLs](https://www.smartrtsp.com/guides/rtsp-url-list) | Same as RTSP |
| **HTTP / MJPEG** (older or cheaper cameras, many phone camera apps) | `http://192.168.1.5:8080/video` | [Comparison of streaming formats](https://bensoftware.com/blog/comparison-of-streaming-formats); [MathWorks: acquiring images from IP cameras](https://www.mathworks.com/help/matlab/supportpkg/acquire-images-from-ip-cameras.html) | Accepted (`http://`, `https://`). Not tested against a real MJPEG camera. Snapshot-only URLs (one JPEG per request) are **not** supported |
| **RTMP / UDP** streams | `rtmp://...`, `udp://...` | Phone and streaming apps | Accepted by the address check; not tested |
| **Webcam / video file** | `0`, `C:\clips\test.mp4` | Plain input | Works (this is the main tested path) |

Notes on the sources: the Hikvision and Dahua paths are consistent across vendor and installer pages, but most are
third-party. The ports (usually 554) and paths can differ by model and firmware, so the camera's own manual wins. IPVM and
the vendor pages disagree on which video codec ONVIF Profile S makes mandatory (MJPEG, or one of MJPEG/MPEG-4/H.264);
cite the ONVIF Profile S specification itself before quoting that detail. H.264/H.265 codecs: H.264 is the common case;
whether H.265 plays depends on the video library installed (not verified here).

## What we actually tested (be ready to say this)

- Video files: yes, the main path.
- A stand-in camera made by `tools/sim_cctv/publish_clip.py` (a clip served as an RTSP stream): rehearsed.
- Connection failures: the Live Monitor names the problem (backend down, relay missing, no picture), and the feed
  reconnects by itself. Covered by automated tests.
- **Not tested:** a real CCTV or DVR, a real phone camera app, MJPEG or RTMP sources, H.265, night or rain footage.

## Limits to state yourself

- Accuracy depends on the camera's angle and quality (blur, glare, small plates). It is in the thesis limitations.
- Opening a barangay's CCTV needs their permission, the recorder's address and its password.
- The system only reads the picture. It does not control the camera (no pan/tilt/zoom) and has no audio.
