const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL as string | undefined)?.replace(/\/$/, '') || '';
const TOKEN_STORAGE_KEY = 'micro_netflix_id_token';

const authHeaders = (): HeadersInit => {
  const token = localStorage.getItem(TOKEN_STORAGE_KEY);
  return token ? { Authorization: token } : {};
};

export interface VideoAsset {
  video_id: string;
  title: string;
  streaming_url: string;
  caption_track_url?: string;
  thumbnail_url?: string;
  ai_summary: string;
  processing_status: string;
  uploaded_at?: string;
  updated_at?: string;
}

export interface CatalogResponse {
  videos: VideoAsset[];
  nextToken?: string | null;
}

export interface UploadRegistration {
  upload_url: string;
  video_id: string;
  s3_key: string;
  title: string;
  thumbnail_upload_url?: string | null;
  thumbnail_key?: string;
}

export const getCatalog = async (options: { limit?: number; nextToken?: string | null; search?: string } = {}): Promise<CatalogResponse> => {
  const params = new URLSearchParams();
  params.set('limit', String(options.limit ?? 12));

  if (options.nextToken) params.set('nextToken', options.nextToken);
  if (options.search?.trim()) params.set('search', options.search.trim());

  const response = await fetch(`${API_BASE_URL}/videos?${params.toString()}`, {
    headers: authHeaders(),
  });
  if (!response.ok) {
    throw new Error(`Catalog request failed with HTTP ${response.status}`);
  }

  const payload = await response.json();
  if (Array.isArray(payload)) {
    return { videos: payload, nextToken: null };
  }

  return {
    videos: Array.isArray(payload.videos) ? payload.videos : [],
    nextToken: payload.nextToken ?? null,
  };
};

export const registerUpload = async (file: File, title: string): Promise<UploadRegistration> => {
  const response = await fetch(`${API_BASE_URL}/upload-url`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...authHeaders() },
    body: JSON.stringify({
      filename: file.name,
      contentType: file.type || 'video/mp4',
      title,
    }),
  });

  if (!response.ok) {
    throw new Error(`Upload registration failed with HTTP ${response.status}`);
  }

  return response.json();
};

export const getStoredIdToken = (): string | null => localStorage.getItem(TOKEN_STORAGE_KEY);

export const storeIdToken = (token: string) => localStorage.setItem(TOKEN_STORAGE_KEY, token);

export const clearStoredIdToken = () => localStorage.removeItem(TOKEN_STORAGE_KEY);

export const uploadToS3 = async (presignedUrl: string, body: Blob, contentType: string): Promise<void> => {
  const response = await fetch(presignedUrl, {
    method: 'PUT',
    headers: { 'Content-Type': contentType },
    body,
  });

  if (!response.ok) {
    throw new Error(`S3 upload failed with HTTP ${response.status}`);
  }
};
