#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wrl.h>
#include <string>
#include <filesystem>
#include "WebView2.h"

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

constexpr int ID_BACK=1001, ID_FORWARD=1002, ID_HOME=1003, ID_RELOAD=1004;
constexpr int ID_YOUTUBE=1101, ID_EDITOR=1102, ID_FILES=1103;
constexpr wchar_t kClass[]=L"YTStudioCoreCloud";
constexpr wchar_t kHome[]=L"https://www.youtube.com/";

HWND gWnd=nullptr;
HWND bBack=nullptr,bForward=nullptr,bHome=nullptr,bReload=nullptr;
HWND tYoutube=nullptr,tEditor=nullptr,tFiles=nullptr;
ComPtr<ICoreWebView2Controller> controller;
ComPtr<ICoreWebView2> webview;

void Layout(){
    RECT r{}; GetClientRect(gWnd,&r);
    int top=92, nav=48;
    int w=r.right-r.left, h=r.bottom-r.top;
    MoveWindow(tYoutube,350,16,130,42,TRUE);
    MoveWindow(tEditor,490,16,130,42,TRUE);
    MoveWindow(tFiles,630,16,130,42,TRUE);
    MoveWindow(bBack,18,top,58,nav-8,TRUE);
    MoveWindow(bForward,84,top,58,nav-8,TRUE);
    MoveWindow(bHome,150,top,94,nav-8,TRUE);
    MoveWindow(bReload,252,top,110,nav-8,TRUE);
    if(controller){
        RECT bounds{0,top+nav,w,h};
        controller->put_Bounds(bounds);
    }
}

void UpdateNav(){
    if(!webview) return;
    BOOL a=FALSE,f=FALSE;
    webview->get_CanGoBack(&a); webview->get_CanGoForward(&f);
    EnableWindow(bBack,a); EnableWindow(bForward,f);
}

void InitWebView(){
    wchar_t local[MAX_PATH]{};
    GetEnvironmentVariableW(L"LOCALAPPDATA",local,MAX_PATH);
    std::filesystem::path data=std::filesystem::path(local)/L"YTStudioCore"/L"WebView2";
    std::error_code ec; std::filesystem::create_directories(data,ec);

    CreateCoreWebView2EnvironmentWithOptions(nullptr,data.c_str(),nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [](HRESULT hr,ICoreWebView2Environment* env)->HRESULT{
          if(FAILED(hr)||!env) return hr;
          return env->CreateCoreWebView2Controller(gWnd,
            Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
              [](HRESULT hr,ICoreWebView2Controller* c)->HRESULT{
                if(FAILED(hr)||!c) return hr;
                controller=c;
                controller->get_CoreWebView2(&webview);
                if(!webview) return E_FAIL;
                ComPtr<ICoreWebView2Settings> s;
                if(SUCCEEDED(webview->get_Settings(&s))&&s){
                  s->put_IsScriptEnabled(TRUE);
                  s->put_AreDefaultContextMenusEnabled(TRUE);
                  s->put_AreDevToolsEnabled(TRUE);
                }
                EventRegistrationToken tok{};
                webview->add_HistoryChanged(
                  Callback<ICoreWebView2HistoryChangedEventHandler>(
                    [](ICoreWebView2*,IUnknown*)->HRESULT{UpdateNav();return S_OK;}).Get(),&tok);
                webview->Navigate(kHome);
                Layout();
                return S_OK;
              }).Get());
        }).Get());
}

LRESULT CALLBACK WndProc(HWND h,UINT m,WPARAM w,LPARAM l){
    switch(m){
    case WM_SIZE: Layout(); return 0;
    case WM_COMMAND:
        switch(LOWORD(w)){
        case ID_BACK: if(webview) webview->GoBack(); break;
        case ID_FORWARD: if(webview) webview->GoForward(); break;
        case ID_HOME: if(webview) webview->Navigate(kHome); break;
        case ID_RELOAD: if(webview) webview->Reload(); break;
        case ID_YOUTUBE: if(webview) webview->Navigate(kHome); break;
        case ID_EDITOR:
            MessageBoxW(h,L"Editor se integrará después de validar la compilación cloud.",L"YT Studio CORE",MB_OK);
            break;
        case ID_FILES:
            MessageBoxW(h,L"Biblioteca se integrará después de validar la compilación cloud.",L"YT Studio CORE",MB_OK);
            break;
        }
        return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(h,m,w,l);
}

HWND Btn(HWND p,const wchar_t* t,int id){
    return CreateWindowW(L"BUTTON",t,WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON,0,0,100,40,p,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),GetModuleHandleW(nullptr),nullptr);
}

int WINAPI wWinMain(HINSTANCE hi,HINSTANCE,LPWSTR,int){
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSEXW wc{sizeof(wc)}; wc.lpfnWndProc=WndProc; wc.hInstance=hi;
    wc.hCursor=LoadCursor(nullptr,IDC_ARROW); wc.hbrBackground=CreateSolidBrush(RGB(3,10,18));
    wc.lpszClassName=kClass; RegisterClassExW(&wc);
    gWnd=CreateWindowExW(0,kClass,L"YT Studio CORE Native - Cloud Build",
      WS_OVERLAPPEDWINDOW|WS_VISIBLE,CW_USEDEFAULT,CW_USEDEFAULT,1440,900,nullptr,nullptr,hi,nullptr);
    bBack=Btn(gWnd,L"<",ID_BACK); bForward=Btn(gWnd,L">",ID_FORWARD);
    bHome=Btn(gWnd,L"INICIO",ID_HOME); bReload=Btn(gWnd,L"RECARGAR",ID_RELOAD);
    tYoutube=Btn(gWnd,L"YOUTUBE",ID_YOUTUBE); tEditor=Btn(gWnd,L"EDITOR",ID_EDITOR); tFiles=Btn(gWnd,L"ARCHIVOS",ID_FILES);
    InitWebView();
    MSG msg{}; while(GetMessageW(&msg,nullptr,0,0)){TranslateMessage(&msg);DispatchMessageW(&msg);}
    controller.Reset(); webview.Reset(); CoUninitialize(); return 0;
}
