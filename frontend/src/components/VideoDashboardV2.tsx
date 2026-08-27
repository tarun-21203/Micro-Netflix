/* eslint-disable react-hooks/set-state-in-effect, react-hooks/exhaustive-deps */
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent } from 'react';
import { clearStoredIdToken, getCatalog, getStoredIdToken, registerUpload, storeIdToken, uploadToS3, type VideoAsset } from '../services/api';
import './VideoDashboardV2.css';

const PAGE_SIZE = 9;
const COGNITO_CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID as string | undefined;
const COGNITO_DOMAIN = (import.meta.env.VITE_COGNITO_DOMAIN as string | undefined)?.replace(/\/$/, '');
const APP_URL = (import.meta.env.VITE_APP_URL as string | undefined)?.replace(/\/$/, '') || window.location.origin;

const fallbackTitle = (fileName: string) => fileName.replace(/\.[^/.]+$/, '').replace(/[_-]+/g, ' ').trim();

const buildThumbnail = (file: File): Promise<Blob | null> => {
  return new Promise((resolve) => {
    const video = document.createElement('video');
    const canvas = document.createElement('canvas');
    const objectUrl = URL.createObjectURL(file);

    const cleanup = () => {
      URL.revokeObjectURL(objectUrl);
      video.removeAttribute('src');
      video.load();
    };

    const finish = () => {
      try {
        const width = video.videoWidth || 1280;
        const height = video.videoHeight || 720;
        canvas.width = width;
        canvas.height = height;
        canvas.getContext('2d')?.drawImage(video, 0, 0, width, height);
        canvas.toBlob((blob) => {
          cleanup();
          resolve(blob);
        }, 'image/jpeg', 0.82);
      } catch {
        cleanup();
        resolve(null);
      }
    };

    video.muted = true;
    video.preload = 'metadata';
    video.playsInline = true;
    video.onloadeddata = () => {
      video.currentTime = Math.min(1, video.duration || 1);
    };
    video.onseeked = finish;
    video.onerror = () => {
      cleanup();
      resolve(null);
    };
    video.src = objectUrl;
  });
};

export default function VideoDashboardV2() {
  const [videos, setVideos] = useState<VideoAsset[]>([]);
  const [selectedVideo, setSelectedVideo] = useState<VideoAsset | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextToken, setNextToken] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [uploadTitle, setUploadTitle] = useState('');
  const [uploading, setUploading] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [uploadStatus, setUploadStatus] = useState('');
  const [idToken, setIdToken] = useState<string | null>(() => getStoredIdToken());
  const sentinelRef = useRef<HTMLDivElement | null>(null);

  const selectedStatus = selectedVideo?.processing_status?.toUpperCase() || '';
  const canPlaySelected = Boolean(selectedVideo?.streaming_url);
  const authConfigured = Boolean(COGNITO_CLIENT_ID && COGNITO_DOMAIN);

  const login = () => {
    if (!COGNITO_CLIENT_ID || !COGNITO_DOMAIN) {
      setUploadStatus('Cognito is not configured in the frontend environment.');
      return;
    }

    const params = new URLSearchParams({
      client_id: COGNITO_CLIENT_ID,
      response_type: 'token',
      scope: 'openid email profile',
      redirect_uri: APP_URL,
    });

    window.location.assign(`${COGNITO_DOMAIN}/login?${params.toString()}`);
  };

  const logout = () => {
    clearStoredIdToken();
    setIdToken(null);
    setVideos([]);
    setSelectedVideo(null);

    if (COGNITO_CLIENT_ID && COGNITO_DOMAIN) {
      const params = new URLSearchParams({
        client_id: COGNITO_CLIENT_ID,
        logout_uri: APP_URL,
      });
      window.location.assign(`${COGNITO_DOMAIN}/logout?${params.toString()}`);
    }
  };

  const loadCatalog = useCallback(async (mode: 'reset' | 'append' = 'reset') => {
    const isAppend = mode === 'append';
    if (isAppend && !nextToken) return;

    if (isAppend) {
      setLoadingMore(true);
    } else {
      setLoading(true);
    }

    try {
      const page = await getCatalog({
        limit: PAGE_SIZE,
        nextToken: isAppend ? nextToken : null,
        search: debouncedSearch,
      });

      setVideos((current) => {
        if (!isAppend) return page.videos;

        const seen = new Set(current.map((video) => video.video_id));
        return [...current, ...page.videos.filter((video) => !seen.has(video.video_id))];
      });
      setNextToken(page.nextToken ?? null);
    } catch (error) {
      setUploadStatus(error instanceof Error ? error.message : 'Catalog refresh failed.');
      if (!isAppend) setVideos([]);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [debouncedSearch, nextToken]);

  useEffect(() => {
    const handle = window.setTimeout(() => setDebouncedSearch(search), 300);
    return () => window.clearTimeout(handle);
  }, [search]);

  useEffect(() => {
    const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ''));
    const token = hashParams.get('id_token');
    if (token) {
      storeIdToken(token);
      setIdToken(token);
      window.history.replaceState(null, document.title, window.location.pathname);
    }
  }, []);

  useEffect(() => {
    if (!idToken) {
      setLoading(false);
      return;
    }
    loadCatalog('reset');
  }, [debouncedSearch, idToken]);

  useEffect(() => {
    if (!sentinelRef.current) return;

    const observer = new IntersectionObserver((entries) => {
      if (entries[0]?.isIntersecting && nextToken && !loading && !loadingMore) {
        loadCatalog('append');
      }
    }, { rootMargin: '600px' });

    observer.observe(sentinelRef.current);
    return () => observer.disconnect();
  }, [loadCatalog, loading, loadingMore, nextToken]);

  const visibleHeading = useMemo(() => {
    if (debouncedSearch) return `Search results for "${debouncedSearch}"`;
    return 'Latest uploads';
  }, [debouncedSearch]);

  const handleFileUpload = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;

    const title = uploadTitle.trim() || fallbackTitle(file.name);

    setUploading(true);
    setUploadStatus(`Preparing upload for ${title}...`);

    try {
      const registration = await registerUpload(file, title);

      setUploadStatus('Generating thumbnail preview...');
      const thumbnail = await buildThumbnail(file);
      if (thumbnail && registration.thumbnail_upload_url) {
        await uploadToS3(registration.thumbnail_upload_url, thumbnail, 'image/jpeg');
      }

      setUploadStatus('Uploading video to S3...');
      await uploadToS3(registration.upload_url, file, file.type || 'video/mp4');

      const previewUrl = thumbnail ? URL.createObjectURL(thumbnail) : '';
      const optimisticAsset: VideoAsset = {
        video_id: registration.video_id,
        title: registration.title || title,
        streaming_url: '',
        thumbnail_url: previewUrl,
        ai_summary: 'Upload complete. Processing will update the catalog shortly.',
        processing_status: 'PROCESSING',
      };

      setVideos((current) => [optimisticAsset, ...current]);
      setUploadTitle('');
      setUploadStatus('Upload complete. Catalog will refresh with playable signed URLs after processing.');
      setUploadOpen(false);

      window.setTimeout(() => loadCatalog('reset'), 8000);
    } catch (error) {
      setUploadStatus(error instanceof Error ? error.message : 'Upload failed.');
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="app-shell">
      <header className="top-bar">
        <div className="brand-block">
          <span className="brand-mark">MN</span>
          <div>
            <h1>Micro-Netflix</h1>
            <p>AI indexed video library</p>
          </div>
        </div>

        <div className="search-box">
          <span aria-hidden="true">Search</span>
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Title, summary, status"
            type="search"
          />
        </div>

        <div className="header-actions">
          {idToken ? (
            <>
              <button className="primary-action" type="button" onClick={() => setUploadOpen(true)}>
                Upload VDO
              </button>
              <button className="secondary-action" type="button" onClick={logout}>
                Sign out
              </button>
            </>
          ) : (
            <button className="primary-action" type="button" onClick={login}>
              Sign in
            </button>
          )}
        </div>
      </header>

      {!idToken && (
        <section className="auth-panel">
          <div>
            <p>Secure cloud streaming</p>
            <h2>Sign in to access your video catalog</h2>
            <span>{authConfigured ? 'Cognito protects uploads, catalog search, and playback metadata.' : 'Cognito environment values are missing. Redeploy to enable login.'}</span>
          </div>
          <button className="primary-action" type="button" onClick={login}>
            Sign in with Cognito
          </button>
        </section>
      )}

      {uploadStatus && !uploadOpen && <div className="status-toast">{uploadStatus}</div>}

      {uploadOpen && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => !uploading && setUploadOpen(false)}>
          <section className="upload-modal" role="dialog" aria-modal="true" aria-labelledby="upload-title" onMouseDown={(event) => event.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 id="upload-title">Upload video</h2>
                <p>Enter a display name or leave it blank to use the file name.</p>
              </div>
              <button className="icon-button" type="button" onClick={() => setUploadOpen(false)} disabled={uploading} aria-label="Close upload">
                X
              </button>
            </div>
            <div className="upload-controls">
              <label>
                <span>Video name</span>
                <input
                  value={uploadTitle}
                  onChange={(event) => setUploadTitle(event.target.value)}
                  placeholder="Optional title"
                  disabled={uploading}
                />
              </label>
              <label className="upload-button">
                <input type="file" accept="video/mp4" onChange={handleFileUpload} disabled={uploading} />
                {uploading ? 'Uploading...' : 'Select MP4'}
              </label>
            </div>
            {uploadStatus && <div className="status-line">{uploadStatus}</div>}
          </section>
        </div>
      )}

      {idToken && !selectedVideo && (
        <section className="browse-hero">
          <div>
            <p>Cloud video library</p>
            <h2>Browse your uploaded videos</h2>
          </div>
          <span>Click a video to open the player.</span>
        </section>
      )}

      {idToken && selectedVideo && (
        <section className="watch-layout">
          <div className="player-column">
            <div className="player-frame">
              {canPlaySelected ? (
                <video
                  key={selectedVideo.video_id}
                  controls
                  crossOrigin="anonymous"
                  preload="metadata"
                  poster={selectedVideo.thumbnail_url || undefined}
                  src={selectedVideo.streaming_url}
                >
                  {selectedVideo.caption_track_url && (
                    <track label="AI captions" kind="subtitles" srcLang="en" src={selectedVideo.caption_track_url} default />
                  )}
                </video>
              ) : (
                <div className="player-placeholder">
                  <span>{selectedStatus === 'COMPLETED' ? 'Preparing signed playback URL' : 'Processing video'}</span>
                </div>
              )}
            </div>
            <h2>{selectedVideo.title}</h2>
          </div>

          <aside className="summary-panel">
            <div className={`pill ${selectedStatus === 'COMPLETED' ? 'ready' : 'pending'}`}>{selectedVideo.processing_status}</div>
            <h3>AI summary</h3>
            <p>{selectedVideo.ai_summary}</p>
          </aside>
        </section>
      )}

      {idToken && <main className="catalog-section">
        <div className="section-title">
          <h2>{visibleHeading}</h2>
          <button type="button" onClick={() => loadCatalog('reset')} disabled={loading || loadingMore}>
            Refresh
          </button>
        </div>

        {loading ? (
          <div className="empty-state">Loading catalog...</div>
        ) : videos.length === 0 ? (
          <div className="empty-state">No videos found.</div>
        ) : (
          <div className="video-grid">
            {videos.map((video) => {
              const status = video.processing_status?.toUpperCase();
              return (
                <button
                  type="button"
                  className={`video-card ${selectedVideo?.video_id === video.video_id ? 'active' : ''}`}
                  key={video.video_id}
                  onClick={() => setSelectedVideo(video)}
                >
                  <div className="thumb">
                    {video.thumbnail_url ? <img src={video.thumbnail_url} alt="" loading="lazy" /> : <span>No preview</span>}
                    <span className={`thumb-status ${status === 'COMPLETED' ? 'ready' : 'pending'}`}>{video.processing_status}</span>
                  </div>
                  <div className="card-copy">
                    <h3>{video.title}</h3>
                    <p>{video.ai_summary}</p>
                  </div>
                </button>
              );
            })}
          </div>
        )}

        <div ref={sentinelRef} className="scroll-sentinel">
          {loadingMore ? 'Loading more videos...' : nextToken ? 'Scroll for more' : ''}
        </div>
      </main>}
    </div>
  );
}
