// DOM元素
const platformSelect = document.getElementById("platform-select");
const searchInput = document.getElementById("search-input");
const searchBtn = document.getElementById("search-btn");
let noResults = document.getElementById("no-results");
const resultFrame = document.getElementById("result-frame");
const bangumiList = document.getElementById("bangumi-list");
const combinedUrlSpan = document.getElementById("combined-url");
const urlInput = document.getElementById("danmaku-url-input");
const copyBtn = document.getElementById("copy-btn");

// 平台搜索URL配置
const platformConfig = {
  bilibili: {
    searchUrl: "https://search.bilibili.com/all?keyword=",
    getDanmakuUrl: function (videoId) {
      return `https://api.bilibili.com/x/v1/dm/list.so?oid=${videoId}`;
    },
    extractVideoId: function (url) {
      // 从B站URL提取视频ID
      const regex = /BV([A-Za-z0-9]{10})|aid=(\d+)/;
      const match = url.match(regex);
      return match ? match[1] || match[2] : null;
    },
  },
  youku: {
    searchUrl: "https://so.youku.com/search/q_",
    getDanmakuUrl: function (videoId) {
      return `https://service.danmu.youku.com/list?vid=${videoId}`;
    },
    extractVideoId: function (url) {
      // 从优酷URL提取视频ID
      const regex = /id_(\w+)/;
      const match = url.match(regex);
      return match ? match[1] : null;
    },
  },
  tencent: {
    searchUrl: "https://v.qq.com/x/search/?q=",
    getDanmakuUrl: function (videoId) {
      return `https://dm.video.qq.com/barrage/segment/${videoId}`;
    },
    extractVideoId: function (url) {
      // 从腾讯视频URL提取视频ID
      const regex = /vid=(\w+)|ep(\d+)/;
      const match = url.match(regex);
      return match ? match[1] || match[2] : null;
    },
  },
  iqiyi: {
    searchUrl: "https://so.iqiyi.com/so/q_",
    getDanmakuUrl: function (videoId) {
      return `https://cmts.iqiyi.com/bullet/${videoId.slice(
        -4,
        -2
      )}/${videoId.slice(-2)}/${videoId}_300_1.z`;
    },
    extractVideoId: function (url) {
      // 从爱奇艺URL提取视频ID
      const regex = /v_(\w+)|aid=(\d+)/;
      const match = url.match(regex);
      return match ? match[1] || match[2] : null;
    },
  },
};

// 执行搜索
function performSearch() {
  const platform = platformSelect.value;
  const keyword = searchInput.value.trim();

  if (!keyword) {
    //   alert('请输入动漫名称');
    return;
  }

  // 隐藏无结果提示
  hideNoResults();

  const config = platformConfig[platform];
  const searchUrl = config.searchUrl + encodeURIComponent(keyword);

  // 在iframe中加载搜索结果
  resultFrame.src = searchUrl;
  
  // 移除自动显示无结果提示的定时器，只在需要时手动调用
  // 设置iframe为不透明，确保搜索结果清晰可见
  resultFrame.style.opacity = "1";
}

// 处理搜索逻辑
function handleSearch() {
  const keyword = searchInput.value.trim();
  const platform = platformSelect.value;
  const config = platformConfig[platform];

  if (!keyword) {
    alert('请输入搜索关键词');
    return;
  }
  
  // 隐藏无结果提示（即动漫列表）
  hideNoResults();

  // 检查输入是否为URL
  if (keyword.startsWith("http://") || keyword.startsWith("https://")) {
    // 尝试从URL中提取视频ID
    const videoId = config.extractVideoId(keyword);
    if (videoId) {
      const danmakuUrl = config.getDanmakuUrl(videoId);
      // 在新窗口中打开弹幕URL或提示用户
      alert(`弹幕下载链接: ${danmakuUrl}`);
      // 也可以直接打开下载
      // window.open(danmakuUrl, '_blank');
    } else {
      alert("无法从URL中提取视频ID，请检查URL是否正确");
    }
  } else {
    // 执行搜索
    performSearch(platform, keyword);
  }
}

// 事件监听
searchBtn.addEventListener("click", function () {
  handleSearch();
});

// 回车键搜索
searchInput.addEventListener("keypress", function (e) {
  if (e.key === "Enter") {
    searchBtn.click();
  }
});

// 显示无结果提示和动漫列表
function showNoResults() {
  // 确保noResults元素存在
  if (!noResults) {
    noResults = document.getElementById("no-results");
  }
  if (noResults) {
    noResults.style.display = "block";
  }
  
  // 同时显示动漫列表
  if (bangumiList) {
    bangumiList.style.display = "block";
  }
  
  // 设置iframe透明度，让提示更明显
  resultFrame.style.opacity = "0.3";
}

// 隐藏无结果提示
function hideNoResults() {
  // 确保noResults元素存在
  if (!noResults) {
    noResults = document.getElementById("no-results");
  }
  if (noResults) {
    noResults.style.display = "none";
  }
  
  // 同时隐藏动漫列表
  if (bangumiList) {
    bangumiList.style.display = "none";
  }
  
  // 恢复iframe不透明度
  resultFrame.style.opacity = "1";
}

// 为iframe添加加载完成事件
resultFrame.addEventListener("load", function () {
  console.log("iframe已加载完成");
  // 注意：由于同源策略限制，我们无法直接操作iframe中的内容
  hideNoResults();
});

// 添加右键菜单功能（可选）
function setupContextMenu() {
  document.addEventListener("contextmenu", function (e) {
    e.preventDefault();
    // 这里可以添加自定义右键菜单逻辑
  });
}

// 从infobox中提取在线播放平台
function extractPlatformFromInfobox(infobox) {
    if (!infobox || !Array.isArray(infobox)) return null;
    
    const platformEntry = infobox.find(item => item.key === '在线播放平台');
    if (!platformEntry) return null;
    
    let platformValue = platformEntry.value;
    
    // 如果value是数组，取第一个值
    if (Array.isArray(platformValue)) {
        platformValue = platformValue[0]?.v || platformValue[0] || '';
    }
    
    // 根据平台名称映射到对应的select值
    if (platformValue.includes('bilibili') || platformValue.includes('B站')) {
        return 'bilibili';
    } else if (platformValue.includes('腾讯视频') || platformValue.includes('腾讯')) {
        return 'tencent';
    } else if (platformValue.includes('优酷')) {
        return 'youku';
    } else if (platformValue.includes('爱奇艺')) {
        return 'iqiyi';
    }
    
    return null;
}

// 获取bangumi接口数据
async function fetchBangumiData() {
    try {
        const apiUrl = "/bangumi_index_subjects.json";
        const response = await fetch(apiUrl);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data.data || [];
    } catch (error) {
        console.error("获取动漫数据失败:", error);
        
        // 返回模拟数据，避免因跨域问题导致页面空白
        return [
            { name_cn: '吞噬星空', infobox: [{ key: '在线播放平台', value: '腾讯视频' }] },
            { name_cn: '三体', infobox: [{ key: '在线播放平台', value: 'bilibili' }] },
            { name_cn: '鬼灭之刃', infobox: [{ key: '在线播放平台', value: 'bilibili' }] },
            { name_cn: '进击的巨人', infobox: [{ key: '在线播放平台', value: 'bilibili' }] },
            { name_cn: '全职高手', infobox: [{ key: '在线播放平台', value: '腾讯视频' }] },
            { name_cn: '斗罗大陆', infobox: [{ key: '在线播放平台', value: '腾讯视频' }] },
            { name_cn: '狐妖小红娘', infobox: [{ key: '在线播放平台', value: '腾讯视频' }] },
            { name_cn: '一人之下', infobox: [{ key: '在线播放平台', value: '腾讯视频' }] }
        ];
    }
}

// 渲染动漫列表
function renderBangumiList(bangumiData) {
  if (!bangumiList) return;

  bangumiList.innerHTML = "";

  bangumiData.forEach((item) => {
    const div = document.createElement("span");
    div.className = "bangumi-item";
    div.textContent = item.name_cn || item.name || "未知动漫";
    
    // 提取平台信息并存储在元素上
    const platform = extractPlatformFromInfobox(item.infobox);
    if (platform) {
        div.setAttribute('data-platform', platform);
    }

    // 添加点击事件
    div.addEventListener("click", function () {
      // 设置搜索框的值
      searchInput.value = item.name_cn || item.name || "";
      
      // 根据提取的平台设置下拉框选项
      if (platform && platformSelect) {
          const option = Array.from(platformSelect.options).find(opt => opt.value === platform);
          if (option) {
              platformSelect.value = platform;
              console.log(`已自动选择平台: ${platform}`);
          }
      }
      
      // 执行搜索
      handleSearch();
    });

    bangumiList.appendChild(div);
  });
}

// 初始化
async function init() {
  setupContextMenu();

  // 初始状态下显示无结果提示
  showNoResults();
  // 设置iframe初始透明度
  resultFrame.style.opacity = "0.3";

  // 获取并渲染动漫列表
  const bangumiData = await fetchBangumiData();
  renderBangumiList(bangumiData);
  
  // 为搜索框添加输入事件监听器
  searchInput.addEventListener("input", function() {
      const keyword = this.value.trim();
      // 当搜索框值为空时显示动漫列表
      if (!keyword) {
          showNoResults();
          // 重置iframe透明度
          resultFrame.style.opacity = "0.3";
      }
  });

  console.log("动漫弹幕搜索工具已初始化");
  
  // 初始化URL拼接功能
  if (urlInput && copyBtn) {
      // 初始化复制按钮状态
      copyBtn.disabled = true;
      
      // 绑定URL输入框事件
      urlInput.addEventListener("input", updateCombinedUrl);
      
      // 绑定复制按钮点击事件
      copyBtn.addEventListener("click", copyCombinedUrl);
      
      // 初始化URL显示
      updateCombinedUrl();
  }
}

// 页面加载完成后初始化
window.addEventListener("load", init);

// 更新拼接后的URL
function updateCombinedUrl() {
    if (!combinedUrlSpan || !urlInput) return;
    
    const baseUrl = "https://fc.lyz05.cn/?url=";
    const videoUrl = urlInput.value.trim();
    
    // 只显示基础URL，完整URL将在复制时生成
    combinedUrlSpan.textContent = baseUrl;
    
    // 根据输入框是否有内容启用/禁用复制按钮
    if (copyBtn) {
        copyBtn.disabled = !videoUrl;
    }
}

// 复制拼接后的URL到剪贴板
async function copyCombinedUrl() {
    if (!urlInput) return;
    
    const videoUrl = urlInput.value.trim();
    if (!videoUrl) {
        alert("请输入视频URL");
        return;
    }
    
    // 生成完整的URL
    const baseUrl = "https://fc.lyz05.cn/?url=";
    const fullUrl = baseUrl + (videoUrl);
    
    try {
        // 使用现代的剪贴板API
        await navigator.clipboard.writeText(fullUrl);
        
        // 复制成功后给用户反馈
        const originalText = copyBtn.textContent;
        copyBtn.textContent = "已复制!";
        copyBtn.style.backgroundColor = "#4CAF50";
        
        // 2秒后恢复按钮状态
        setTimeout(() => {
            copyBtn.textContent = originalText;
            copyBtn.style.backgroundColor = "";
        }, 2000);
    } catch (err) {
        console.error("复制失败:", err);
        
        // 降级方案：使用传统的方法
        try {
            const textArea = document.createElement("textarea");
            textArea.value = fullUrl;
            textArea.style.position = "fixed";
            textArea.style.left = "-999999px";
            textArea.style.top = "-999999px";
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            
            const successful = document.execCommand("copy");
            if (successful) {
                const originalText = copyBtn.textContent;
                copyBtn.textContent = "已复制!";
                copyBtn.style.backgroundColor = "#4CAF50";
                
                setTimeout(() => {
                    copyBtn.textContent = originalText;
                    copyBtn.style.backgroundColor = "";
                }, 2000);
            } else {
                alert("复制失败，请手动复制:", fullUrl);
            }
        } catch (fallbackErr) {
            console.error("降级方案也失败:", fallbackErr);
            alert("复制失败，请手动复制URL");
        } finally {
            const textArea = document.querySelector("textarea[style*='left: -999999px']");
            if (textArea) {
                document.body.removeChild(textArea);
            }
        }
    }
}
