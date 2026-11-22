import { createServerClient, type SetAllCookies } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Keeps the staff session fresh and protects the kitchen screen.
 * Guest routes (/r/...) and the API pass straight through.
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  // The library hands over the no-cache headers only on the first cookie write,
  // but `response` is rebuilt on every write. Keep them here to reapply each time.
  let cacheHeaders: Record<string, string> = {};

  const setAll: SetAllCookies = (cookiesToSet, headers) => {
    cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
    response = NextResponse.next({ request });
    cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
    cacheHeaders = { ...cacheHeaders, ...headers };
    Object.entries(cacheHeaders).forEach(([key, value]) => response.headers.set(key, value));
  };

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll,
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user && request.nextUrl.pathname.startsWith("/kitchen")) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", request.nextUrl.pathname);
    const redirect = NextResponse.redirect(url);
    // A failed refresh may have rewritten or cleared the session cookies; the redirect
    // must carry them (and the no-cache headers) or the browser keeps the stale ones.
    response.cookies.getAll().forEach((cookie) => redirect.cookies.set(cookie));
    Object.entries(cacheHeaders).forEach(([key, value]) => redirect.headers.set(key, value));
    return redirect;
  }

  return response;
}

export const config = {
  matcher: ["/kitchen/:path*", "/login"],
};
