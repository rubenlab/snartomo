<script setup lang="ts">
import { useRouter, RouterView } from "vue-router";
import { ref } from "vue";
import type { TabsPaneContext } from "element-plus";

const activeName = ref("/");
const router = useRouter();
const handleClick = (tab: TabsPaneContext, event: Event) => {
  router.push({ path: tab.paneName as string });
};
</script>

<template>
  <el-header>
    <el-tabs
      v-model="activeName"
      type="card"
      class="demo-tabs"
      @tab-click="handleClick"
    >
      <el-tab-pane label="PACE" name="/"></el-tab-pane>
      <el-tab-pane label="Classic" name="/classic"></el-tab-pane>
      <el-tab-pane label="FrameCalc" name="/framecalc"></el-tab-pane>
    </el-tabs>
  </el-header>
  <el-main>
    <RouterView />
  </el-main>
</template>

<style>
@import "@/assets/base.css";
</style>
