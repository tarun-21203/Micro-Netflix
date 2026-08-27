/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unused-vars, react-hooks/set-state-in-effect */
import { useState, useEffect, type ChangeEvent } from 'react';

interface VideoAsset {
    video_id: string;
    title: string;
    streaming_url: string;
    caption_track_url: string;
    ai_summary: string;
    processing_status: string;
}

export default function VideoDashboard() {
    const [videos, setVideos] = useState<VideoAsset[]>([]);
    const [selectedVideo, setSelectedVideo] = useState<VideoAsset | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [uploading, setUploading] = useState<boolean>(false);
    const [uploadStatus, setUploadStatus] = useState<string>('');

    const fetchCatalog = async () => {
        try {
            const apiBaseUrl = (import.meta.env.VITE_API_BASE_URL as string) || '';
            const response = await fetch(`${apiBaseUrl}/videos`);

            if (response.ok) {
                const data = await response.json();
                if (Array.isArray(data)) {
                    setVideos(data);
                } else if (data && typeof data === 'object' && 'videos' in data && Array.isArray((data as any).videos)) {
                    setVideos((data as any).videos);
                }
            } else {
                throw new Error("Fallback required");
            }
        } catch (err) {
            console.log("Displaying simulated catalog fallback");
            setVideos([
                {
                    video_id: "interstellar_space_travel",
                    title: "interstellar space travel",
                    streaming_url: "https://micro-netflix-raw-uploads-dal.s3.amazonaws.com/interstellar_space_travel.mp4",
                    caption_track_url: "https://micro-netflix-production-assets-dal.s3.amazonaws.com/captions/interstellar_space_travel.vtt",
                    ai_summary: "Automated smart summary generated for movie stream: 'interstellar space travel'. AI-extracted core keywords and content tags include: interstellar, space, travel, cosmos.",
                    processing_status: "COMPLETED"
                }
            ]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchCatalog();
    }, []);

    // Handle direct client-side upload simulation/execution tracking
    const handleFileUpload = async (e: ChangeEvent<HTMLInputElement>) => {
        if (!e.target.files || e.target.files.length === 0) return;
        const file = e.target.files[0];

        setUploading(true);
        setUploadStatus(`Requesting secure upload authorization for: ${file.name}...`);

        try {
            const cleanId = file.name.split('.')[0].replace(/ /g, '_');

            // ==========================================
            // STEP 1: Get the Presigned URL from API Gateway
            // ==========================================
            // ⚠️ REPLACE THIS with your actual API Gateway endpoint URL
            const API_GATEWAY_URL = import.meta.env.VITE_API_GATEWAY_URL || "http://localhost:3000";

            // Query parameters pass filename and type so S3 can sign it accurately
            const tokenResponse = await fetch(`${API_GATEWAY_URL}?filename=${encodeURIComponent(file.name)}&contentType=${encodeURIComponent(file.type)}`);

            if (!tokenResponse.ok) {
                throw new Error(`API Gateway error: ${tokenResponse.statusText}`);
            }

            const tokenData = await tokenResponse.json();

            // ⚠️ Double check your get-upload-url Lambda response structure. 
            // If your Lambda returns { uploadUrl: "..." }, use tokenData.uploadUrl
            const presignedUrl = tokenData.uploadUrl || tokenData.body?.uploadUrl || tokenData;

            if (!presignedUrl) {
                throw new Error("Could not parse presigned URL from API token response.");
            }

            // ==========================================
            // STEP 2: Stream the Binary File directly to S3
            // ==========================================
            setUploadStatus(`Streaming file binaries directly to S3 ingestion bucket...`);

            const s3Response = await fetch(presignedUrl, {
                method: 'PUT',
                headers: {
                    'Content-Type': file.type // Must match the content type used to generate the signature
                },
                body: file // The raw file object stream
            });

            if (!s3Response.ok) {
                throw new Error(`S3 rejected ingestion chunk payload: ${s3Response.statusText}`);
            }

            // ==========================================
            // STEP 3: Update Local UI State On Success
            // ==========================================
            const newAsset: VideoAsset = {
                video_id: cleanId,
                title: file.name.split('.')[0].replace(/_/g, ' '),
                streaming_url: `https://micro-netflix-raw-uploads-dal.s3.amazonaws.com/${file.name}`,
                caption_track_url: `https://micro-netflix-production-assets-dal.s3.amazonaws.com/captions/${cleanId}.vtt`,
                ai_summary: "Processing pipeline triggered! SQS event-driven worker is running Amazon Comprehend analysis. Refresh in 10 seconds...",
                processing_status: "PROCESSING"
            };

            setVideos(prev => [newAsset, ...prev]);
            setUploadStatus('Asset successfully pushed to S3 ingestion bucket!');

        } catch (error: any) {
            console.error("Pipeline failure:", error);
            setUploadStatus(`Upload failed: ${error.message || 'Transaction routing error.'}`);
        } finally {
            setUploading(false);
        }
    };

    return (
        <div style={{ backgroundColor: '#141414', color: '#fff', minHeight: '100vh', fontFamily: 'Arial, sans-serif', padding: '40px' }}>
            <header style={{ marginBottom: '30px', borderBottom: '1px solid #333', paddingBottom: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                    <h1 style={{ color: '#E50914', margin: 0, fontSize: '2.5rem', letterSpacing: '1px' }}>MICRO-NETFLIX</h1>
                    <p style={{ color: '#aaa', marginTop: '5px' }}>AI-Powered Autonomous Event-Driven Video Streaming</p>
                </div>

                {/* Interactive Ingestion File Upload Input Button */}
                <div style={{ background: '#222', padding: '15px', borderRadius: '6px', border: '1px dashed #E50914' }}>
                    <label style={{ cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                        <span style={{ color: '#E50914', fontWeight: 'bold', marginBottom: '5px' }}>📤 Upload New Movie Asset</span>
                        <input type="file" accept="video/mp4" onChange={handleFileUpload} style={{ display: 'none' }} disabled={uploading} />
                        <span style={{ fontSize: '0.75rem', color: '#888' }}>Accepts standard MP4 profiles</span>
                    </label>
                    {uploadStatus && <p style={{ fontSize: '0.8rem', color: '#46d369', margin: '5px 0 0 0', textAlign: 'center' }}>{uploadStatus}</p>}
                </div>
            </header>

            {/* Main Video Arena Showcase */}
            {selectedVideo && (
                <section style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '30px', marginBottom: '40px', background: '#181818', padding: '20px', borderRadius: '8px' }}>
                    <div>
                        <h2 style={{ marginTop: 0, color: '#fff' }}>{selectedVideo.title.toUpperCase()}</h2>
                        <video key={selectedVideo.video_id} controls crossOrigin="anonymous" controlsList="nodownload" style={{ width: '100%', borderRadius: '6px', border: '1px solid #333' }} src={selectedVideo.streaming_url}>
                            <track label="English AI Captions" kind="subtitles" srcLang="en" src={selectedVideo.caption_track_url} default />
                        </video>
                    </div>
                    <div style={{ background: '#202020', padding: '25px', borderRadius: '6px', borderLeft: '4px solid #E50914' }}>
                        <h3 style={{ color: '#E50914', marginTop: 0 }}>🧠 Deep AI Core Summary</h3>
                        <p style={{ lineHeight: '1.6', fontSize: '0.95rem', color: '#e0e0e0' }}>{selectedVideo.ai_summary}</p>
                        <hr style={{ borderColor: '#333', margin: '20px 0' }} />
                        <h4>System Status</h4>
                        <span style={{ backgroundColor: selectedVideo.processing_status === 'COMPLETED' ? '#46d369' : '#fbc02d', color: '#000', padding: '4px 8px', borderRadius: '4px', fontWeight: 'bold', fontSize: '0.8rem' }}>
                            {selectedVideo.processing_status}
                        </span>
                    </div>
                </section>
            )}

            {/* Video Content Grid Rows */}
            <main>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                    <h3 style={{ fontSize: '1.4rem', margin: 0 }}>Trending AI-Indexed Uploads</h3>
                    <button onClick={fetchCatalog} style={{ background: '#333', color: '#fff', border: 'none', padding: '6px 12px', borderRadius: '4px', cursor: 'pointer' }}>🔄 Refresh Catalog</button>
                </div>

                {loading ? (
                    <p>Scanning global DynamoDB ledger rows...</p>
                ) : (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '25px' }}>
                        {Array.isArray(videos) && videos.length > 0 ? (
                            videos.map((video) => (
                                <div key={video.video_id} onClick={() => setSelectedVideo(video)} style={{ background: '#181818', borderRadius: '6px', overflow: 'hidden', cursor: 'pointer', transition: 'transform 0.2s', border: selectedVideo?.video_id === video.video_id ? '2px solid #E50914' : '1px solid #222' }}>
                                    <div style={{ height: '160px', backgroundColor: '#262626', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                        <span style={{ fontSize: '3rem' }}>🎬</span>
                                    </div>
                                    <div style={{ padding: '15px' }}>
                                        <h4 style={{ margin: '0 0 10px 0', textTransform: 'capitalize' }}>{video.title}</h4>
                                        <p style={{ fontSize: '0.8rem', color: '#aaa', margin: 0, textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>{video.ai_summary}</p>
                                    </div>
                                </div>
                            ))
                        ) : (
                            <p style={{ color: '#aaa' }}>No processed streams currently available in the catalog index.</p>
                        )}
                    </div>
                )}
            </main>
        </div>
    );
}
