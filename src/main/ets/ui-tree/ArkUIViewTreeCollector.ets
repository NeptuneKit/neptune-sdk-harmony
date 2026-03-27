import { ExpandMode, FrameNode, UIContext } from '@kit.ArkUI'
import { AbilityConstant, Configuration, EnvironmentCallback } from '@kit.AbilityKit'
import {
  ExportInspectorSnapshot,
  ExportViewTreeFrame,
  ExportViewTreeNode,
  ExportViewTreeSnapshot,
  ExportViewTreeStyle,
  Platform,
  ViewTreeQueryOptions
} from '../model/LogModels'

interface InspectorNode {
  $type?: string
  $ID?: number
  $rect?: string
  $attrs?: InspectorAttrs
  $children?: InspectorNode[]
}

interface InspectorAttrs {
  id?: string
  opacity?: string | number
  alpha?: string | number
  backgroundColor?: string
  background?: string
  bgColor?: string
  fill?: string
  fontColor?: string
  textColor?: string
  color?: string
  fontSize?: string | number
  lineHeight?: string | number
  letterSpacing?: string | number
  fontWeight?: string
  fontWeightRaw?: string
  borderRadius?: string | number
  radius?: string | number
  borderWidth?: string | number
  borderColor?: string
  stroke?: string
  strokeWidth?: string | number
  zIndex?: string | number
  textAlign?: string
  textAlignHorizontal?: string
  align?: string
  content?: string
  text?: string
  value?: string
  label?: string
  visible?: boolean | string
  visibility?: string
}

interface InspectorEnvelope extends InspectorNode {
  type?: string
  content?: InspectorNode
}

type TypographySourceUnit = 'vp' | 'fp' | 'px'

interface TypographyMeasurement {
  value: number
  sourceUnit?: TypographySourceUnit
}

type InspectorValue = Object | string | number | boolean | null

export class ArkUIViewTreeCollector {
  private uiContext: UIContext | null = null
  private viewTreeAnchorUniqueId: number | null = null
  private typographyFontScale: number = 1
  private typographyEnvironmentCallbackId: number | null = null

  setUIContext(context: UIContext | undefined | null): void {
    if (context === undefined || context === null) {
      return
    }
    this.uiContext = context
    this.updateTypographyScaleListener(context)
  }

  setViewTreeAnchorUniqueId(uniqueId: number | undefined | null): void {
    if (uniqueId === undefined || uniqueId === null || uniqueId <= 0) {
      return
    }
    this.viewTreeAnchorUniqueId = uniqueId
  }

  captureViewTreeSnapshot(query: ViewTreeQueryOptions): ExportViewTreeSnapshot {
    const platform = this.normalizeViewTreePlatform(query.platform)
    const inspectorRoot = this.resolveInspectorRootNode()
    const roots = inspectorRoot !== null
      ? [this.toInspectorViewTreeNode(inspectorRoot, null, 'inspector-root')]
      : this.captureFrameNodeRoots()
    return {
      snapshotId: `harmony-ui-tree-${Date.now()}`,
      capturedAt: new Date().toISOString(),
      platform,
      roots
    }
  }

  captureInspectorSnapshot(query: ViewTreeQueryOptions): ExportInspectorSnapshot {
    const platform = this.normalizeViewTreePlatform(query.platform)
    const capturedAt = new Date().toISOString()
    if (this.uiContext === null) {
      return {
        snapshotId: `harmony-inspector-${Date.now()}`,
        capturedAt,
        platform,
        available: false,
        payload: null,
        reason: 'UIContext unavailable.'
      }
    }

    try {
      const payloadRaw = this.getInspectorTreePayload()
      const payload = this.normalizeInspectorPayload(JSON.parse(payloadRaw)) as Object
      this.trySyncAnchorUniqueIdFromInspectorPayload(payload)
      const normalizedPayload = this.normalizeTypographyInspectorPayload(payload) as Object
      return {
        snapshotId: `harmony-inspector-${Date.now()}`,
        capturedAt,
        platform,
        available: true,
        payload: normalizedPayload
      }
    } catch (error) {
      return {
        snapshotId: `harmony-inspector-${Date.now()}`,
        capturedAt,
        platform,
        available: false,
        payload: null,
        reason: error instanceof Error ? error.message : String(error)
      }
    }
  }

  private resolveInspectorRootNode(): InspectorNode | null {
    if (this.uiContext === null) {
      return null
    }

    try {
      const payload = this.getInspectorTreePayload()
      const parsed = this.normalizeInspectorPayload(JSON.parse(payload)) as InspectorEnvelope
      this.trySyncAnchorUniqueIdFromInspectorPayload(parsed as Object)
      if (parsed.content !== undefined && parsed.content !== null) {
        return parsed.content
      }
      return parsed
    } catch (_error) {
      return null
    }
  }

  private toInspectorViewTreeNode(
    node: InspectorNode,
    parentId: string | null,
    fallbackId: string
  ): ExportViewTreeNode {
    const nodeId = this.normalizeInspectorNodeId(node, fallbackId)
    const name = this.normalizeInspectorNodeType(node.$type)
    const frame = this.parseInspectorFrame(node.$rect) ?? this.readFrameFromInspectorId(node.$ID)
    const style = this.parseInspectorStyle(node.$attrs)
    const text = this.parseInspectorText(node.$attrs)
    const visible = this.parseInspectorVisible(node.$attrs)
    const rawChildren = node.$children ?? []
    const children: ExportViewTreeNode[] = []
    for (let index = 0; index < rawChildren.length; index += 1) {
      const child = rawChildren[index]
      children.push(this.toInspectorViewTreeNode(child, nodeId, `${nodeId}-${String(index)}`))
    }
    return {
      id: nodeId,
      parentId,
      name,
      frame,
      style,
      text,
      visible,
      children
    }
  }

  private parseInspectorFrame(rawRect: string | undefined): ExportViewTreeFrame | undefined {
    if (rawRect === undefined) {
      return undefined
    }

    const values = rawRect.match(/-?\d+(?:\.\d+)?/g)
    if (values === null || values.length < 4) {
      return undefined
    }
    const left = Number.parseFloat(values[0])
    const top = Number.parseFloat(values[1])
    const right = Number.parseFloat(values[2])
    const bottom = Number.parseFloat(values[3])
    if (!Number.isFinite(left) || !Number.isFinite(top) || !Number.isFinite(right) || !Number.isFinite(bottom)) {
      return undefined
    }
    return {
      x: left,
      y: top,
      width: Math.max(0, right - left),
      height: Math.max(0, bottom - top)
    }
  }

  private readFrameFromInspectorId(uniqueId: number | undefined): ExportViewTreeFrame | undefined {
    if (this.uiContext === null || uniqueId === undefined || !Number.isFinite(uniqueId)) {
      return undefined
    }

    const node = this.uiContext.getFrameNodeByUniqueId(uniqueId)
    if (node === null) {
      return undefined
    }

    try {
      const position = node.getPositionToWindow()
      const size = node.getMeasuredSize()
      if (
        !Number.isFinite(position.x) ||
        !Number.isFinite(position.y) ||
        !Number.isFinite(size.width) ||
        !Number.isFinite(size.height)
      ) {
        return undefined
      }
      return {
        x: position.x,
        y: position.y,
        width: Math.max(0, size.width),
        height: Math.max(0, size.height)
      }
    } catch (_error) {
      return undefined
    }
  }

  private parseInspectorStyle(attrs: InspectorAttrs | undefined): ExportViewTreeStyle | undefined {
    if (attrs === undefined) {
      return undefined
    }

    const style: ExportViewTreeStyle = {}
    style.opacity = this.readAttrNumber(attrs, ['opacity', 'alpha'])
    style.backgroundColor = this.readAttrString(attrs, ['backgroundColor', 'background', 'bgColor', 'fill'])
    style.textColor = this.readAttrString(attrs, ['fontColor', 'textColor', 'color'])
    const fontSizeMeasurement = this.readTypographyMeasurement(attrs, ['fontSize'], 'vp')
    const lineHeightMeasurement = this.readTypographyMeasurement(attrs, ['lineHeight'], 'fp')
    const letterSpacingMeasurement = this.readTypographyMeasurement(attrs, ['letterSpacing'], 'fp')
    const fontWeight = this.readAttrText(attrs, ['fontWeightRaw', 'fontWeight'])

    style.fontSize = fontSizeMeasurement?.value
    style.lineHeight = lineHeightMeasurement?.value
    style.letterSpacing = letterSpacingMeasurement?.value
    style.sourceTypographyUnit =
      fontSizeMeasurement?.sourceUnit ??
      lineHeightMeasurement?.sourceUnit ??
      letterSpacingMeasurement?.sourceUnit
    style.fontWeight = fontWeight
    style.fontWeightRaw = fontWeight
    style.borderRadius = this.readAttrNumber(attrs, ['borderRadius', 'radius'])
    style.borderWidth = this.readAttrNumber(attrs, ['borderWidth', 'strokeWidth'])
    style.borderColor = this.readAttrString(attrs, ['borderColor', 'stroke'])
    style.zIndex = this.readAttrNumber(attrs, ['zIndex'])
    style.textAlign = this.readAttrString(attrs, ['textAlign', 'textAlignHorizontal', 'align'])
    if (
      style.fontSize !== undefined ||
      style.lineHeight !== undefined ||
      style.letterSpacing !== undefined
    ) {
      style.typographyUnit = 'dp'
      style.platformFontScale = this.resolveTypographyFontScale()
    }

    if (
      style.opacity === undefined &&
      style.backgroundColor === undefined &&
      style.textColor === undefined &&
      style.fontSize === undefined &&
      style.lineHeight === undefined &&
      style.letterSpacing === undefined &&
      style.typographyUnit === undefined &&
      style.sourceTypographyUnit === undefined &&
      style.platformFontScale === undefined &&
      style.fontWeight === undefined &&
      style.fontWeightRaw === undefined &&
      style.borderRadius === undefined &&
      style.borderWidth === undefined &&
      style.borderColor === undefined &&
      style.zIndex === undefined &&
      style.textAlign === undefined
    ) {
      return undefined
    }
    return style
  }

  private parseInspectorText(attrs: InspectorAttrs | undefined): string | undefined {
    if (attrs === undefined) {
      return undefined
    }
    return this.readAttrString(attrs, ['content', 'text', 'value', 'label'])
  }

  private parseInspectorVisible(attrs: InspectorAttrs | undefined): boolean | undefined {
    if (attrs === undefined) {
      return undefined
    }

    const visible = this.readAttrBoolean(attrs, ['visible'])
    if (visible !== undefined) {
      return visible
    }
    const visibility = this.readAttrString(attrs, ['visibility'])
    if (visibility === undefined) {
      return undefined
    }
    const normalized = visibility.toLowerCase()
    return normalized !== 'hidden' && normalized !== 'gone' && normalized !== 'none'
  }

  private readAttrString(attrs: InspectorAttrs, keys: string[]): string | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      if (typeof raw === 'string') {
        const normalized = raw.trim()
        if (normalized.length > 0) {
          return normalized
        }
      }
    }
    return undefined
  }

  private readAttrText(attrs: InspectorAttrs, keys: string[]): string | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      const text = this.normalizeTypographyText(raw)
      if (text !== undefined) {
        return text
      }
    }
    return undefined
  }

  private readAttrNumber(attrs: InspectorAttrs, keys: string[]): number | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      if (typeof raw === 'number' && Number.isFinite(raw)) {
        return raw
      }
      if (typeof raw === 'string') {
        const parsed = Number.parseFloat(raw)
        if (Number.isFinite(parsed)) {
          return parsed
        }
      }
    }
    return undefined
  }

  private readTypographyMeasurement(
    attrs: InspectorAttrs,
    keys: string[],
    defaultUnit: 'vp' | 'fp'
  ): TypographyMeasurement | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      const value = this.normalizeTypographyMeasurement(raw, defaultUnit)
      if (value !== undefined) {
        return value
      }
    }
    return undefined
  }

  private normalizeTypographyMeasurement(
    raw: string | number | boolean | null | undefined,
    defaultUnit: 'vp' | 'fp'
  ): TypographyMeasurement | undefined {
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return {
        value: this.convertTypographyNumber(raw, defaultUnit),
        sourceUnit: defaultUnit
      }
    }

    if (typeof raw !== 'string') {
      return undefined
    }

    const trimmed = raw.trim()
    if (trimmed.length === 0) {
      return undefined
    }

    const match = trimmed.match(/^(-?\d+(?:\.\d+)?)([a-zA-Z%]+)?$/)
    if (match === null) {
      const parsed = Number.parseFloat(trimmed)
      if (Number.isFinite(parsed)) {
        return {
          value: this.convertTypographyNumber(parsed, defaultUnit),
          sourceUnit: defaultUnit
        }
      }
      return undefined
    }

    const value = Number.parseFloat(match[1])
    if (!Number.isFinite(value)) {
      return undefined
    }

    const unit = this.normalizeTypographySourceUnit(match[2], defaultUnit)
    if (unit === null) {
      return undefined
    }
    return {
      value: this.convertTypographyNumber(value, unit),
      sourceUnit: unit
    }
  }

  private normalizeTypographySourceUnit(
    rawUnit: string | undefined,
    defaultUnit: 'vp' | 'fp'
  ): 'vp' | 'fp' | 'px' | null {
    const normalized = rawUnit?.trim().toLowerCase() ?? ''
    if (normalized.length === 0) {
      return defaultUnit
    }
    if (normalized === 'dp' || normalized === 'vp') {
      return 'vp'
    }
    if (normalized === 'fp') {
      return 'fp'
    }
    if (normalized === 'px') {
      return 'px'
    }
    return null
  }

  private convertTypographyNumber(value: number, unit: 'vp' | 'fp' | 'px'): number {
    switch (unit) {
      case 'vp':
        return value
      case 'fp':
        return value * this.resolveTypographyFontScale()
      case 'px':
        return this.convertPxToDp(value)
      default:
        return value
    }
  }

  private convertPxToDp(value: number): number {
    if (this.uiContext === null) {
      return value
    }

    try {
      return this.uiContext.px2vp(value)
    } catch (_error) {
      return value
    }
  }

  private resolveTypographyFontScale(): number {
    if (Number.isFinite(this.typographyFontScale) && this.typographyFontScale > 0) {
      return this.typographyFontScale
    }
    return 1
  }

  private normalizeTypographyText(
    raw: string | number | boolean | null | undefined
  ): string | undefined {
    if (typeof raw === 'string') {
      const normalized = raw.trim()
      return normalized.length > 0 ? normalized : undefined
    }

    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return String(raw)
    }

    if (typeof raw === 'boolean') {
      return String(raw)
    }

    return undefined
  }

  private updateTypographyScaleListener(context: UIContext): void {
    if (this.typographyEnvironmentCallbackId !== null) {
      return
    }

    const hostContext = context.getHostContext()
    const applicationContext = hostContext?.getApplicationContext()
    if (applicationContext === undefined) {
      return
    }

    const environmentCallback: EnvironmentCallback = {
      onConfigurationUpdated: (config: Configuration): void => {
        this.updateTypographyFontScale(config)
      },
      onMemoryLevel: (_level: AbilityConstant.MemoryLevel): void => {
      }
    }

    try {
      this.typographyEnvironmentCallbackId = applicationContext.on('environment', environmentCallback)
    } catch (_error) {
      this.typographyEnvironmentCallbackId = null
    }
  }

  private updateTypographyFontScale(config: Configuration): void {
    const fontSizeScale = config.fontSizeScale
    if (typeof fontSizeScale === 'number' && Number.isFinite(fontSizeScale) && fontSizeScale > 0) {
      this.typographyFontScale = fontSizeScale
    }
  }

  private readAttrBoolean(attrs: InspectorAttrs, keys: string[]): boolean | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      if (typeof raw === 'boolean') {
        return raw
      }
      if (typeof raw === 'string') {
        if (raw === 'true') {
          return true
        }
        if (raw === 'false') {
          return false
        }
      }
    }
    return undefined
  }

  private readInspectorAttrValue(
    attrs: InspectorAttrs,
    key: string
  ): string | number | boolean | null | undefined {
    switch (key) {
      case 'id':
        return attrs.id
      case 'opacity':
        return attrs.opacity
      case 'alpha':
        return attrs.alpha
      case 'backgroundColor':
        return attrs.backgroundColor
      case 'background':
        return attrs.background
      case 'bgColor':
        return attrs.bgColor
      case 'fill':
        return attrs.fill
      case 'fontColor':
        return attrs.fontColor
      case 'textColor':
        return attrs.textColor
      case 'color':
        return attrs.color
      case 'fontSize':
        return attrs.fontSize
      case 'fontWeight':
        return attrs.fontWeight
      case 'fontWeightRaw':
        return attrs.fontWeightRaw
      case 'borderRadius':
        return attrs.borderRadius
      case 'radius':
        return attrs.radius
      case 'borderWidth':
        return attrs.borderWidth
      case 'borderColor':
        return attrs.borderColor
      case 'stroke':
        return attrs.stroke
      case 'strokeWidth':
        return attrs.strokeWidth
      case 'zIndex':
        return attrs.zIndex
      case 'textAlign':
        return attrs.textAlign
      case 'textAlignHorizontal':
        return attrs.textAlignHorizontal
      case 'align':
        return attrs.align
      case 'content':
        return attrs.content
      case 'text':
        return attrs.text
      case 'value':
        return attrs.value
      case 'label':
        return attrs.label
      case 'visible':
        return attrs.visible
      case 'visibility':
        return attrs.visibility
      default:
        return undefined
    }
  }

  private normalizeInspectorNodeId(node: InspectorNode, fallbackId: string): string {
    const attrId = node.$attrs?.id?.trim() ?? ''
    if (attrId.length > 0) {
      return attrId
    }

    if (node.$ID !== undefined && Number.isFinite(node.$ID)) {
      return `inspector-${String(node.$ID)}`
    }
    return fallbackId
  }

  private normalizeInspectorNodeType(rawType: string | undefined): string {
    if (rawType === undefined) {
      return 'UnknownNode'
    }
    const normalized = rawType.trim()
    return normalized.length > 0 ? normalized : 'UnknownNode'
  }

  private trySyncAnchorUniqueIdFromInspectorPayload(payload: Object): void {
    const root = payload as InspectorEnvelope
    const rootNode = root.content !== undefined && root.content !== null
      ? root.content
      : root
    const uniqueId = rootNode.$ID
    if (uniqueId === undefined || !Number.isFinite(uniqueId) || uniqueId <= 0) {
      return
    }
    this.viewTreeAnchorUniqueId = uniqueId
  }

  private getInspectorTreePayload(): string {
    if (this.uiContext === null) {
      return '{}'
    }

    try {
      return this.uiContext.getFilteredInspectorTree(['isLayoutInspector'])
    } catch (_error) {
      try {
        return this.uiContext.getFilteredInspectorTree()
      } catch (_fallbackError) {
        try {
          return this.uiContext.getFilteredInspectorTree(['content'])
        } catch (_finalError) {
          return '{}'
        }
      }
    }
  }

  private normalizeInspectorPayload(value: InspectorValue): InspectorValue {
    if (value === null) {
      return null
    }

    if (typeof value === 'string') {
      return this.parseEmbeddedJsonString(value)
    }

    if (Array.isArray(value)) {
      const normalizedArray: InspectorValue[] = []
      const items = value as InspectorValue[]
      for (let index = 0; index < items.length; index += 1) {
        normalizedArray.push(this.normalizeInspectorPayload(items[index]))
      }
      return normalizedArray as Object
    }

    if (typeof value !== 'object') {
      return value
    }

    const normalizedObject: Record<string, InspectorValue> = {}
    for (const key of Object.keys(value)) {
      const raw = (value as Record<string, InspectorValue>)[key]
      normalizedObject[key] = this.normalizeInspectorPayload(raw)
    }
    return normalizedObject
  }

  private normalizeTypographyInspectorPayload(value: InspectorValue): InspectorValue {
    if (value === null) {
      return null
    }

    if (Array.isArray(value)) {
      const normalizedArray: InspectorValue[] = []
      const items = value as InspectorValue[]
      for (let index = 0; index < items.length; index += 1) {
        normalizedArray.push(this.normalizeTypographyInspectorPayload(items[index]))
      }
      return normalizedArray as Object
    }

    if (typeof value !== 'object') {
      return value
    }

    const normalizedObject = value as Record<string, InspectorValue>
    const attrs = normalizedObject.$attrs
    if (attrs !== undefined && attrs !== null && typeof attrs === 'object' && !Array.isArray(attrs)) {
      const normalizedAttrs = attrs as Record<string, InspectorValue>
      const fontSizeMeasurement = this.normalizeTypographyMeasurement(
        normalizedAttrs.fontSize as string | number | boolean | null | undefined,
        'vp'
      )
      const lineHeightMeasurement = this.normalizeTypographyMeasurement(
        normalizedAttrs.lineHeight as string | number | boolean | null | undefined,
        'fp'
      )
      const letterSpacingMeasurement = this.normalizeTypographyMeasurement(
        normalizedAttrs.letterSpacing as string | number | boolean | null | undefined,
        'fp'
      )
      const fontWeight = this.normalizeTypographyText(
        normalizedAttrs.fontWeightRaw as string | number | boolean | null | undefined
      ) ?? this.normalizeTypographyText(
        normalizedAttrs.fontWeight as string | number | boolean | null | undefined
      )
      if (fontSizeMeasurement !== undefined) {
        normalizedAttrs.fontSize = fontSizeMeasurement.value
      }
      if (lineHeightMeasurement !== undefined) {
        normalizedAttrs.lineHeight = lineHeightMeasurement.value
      }
      if (letterSpacingMeasurement !== undefined) {
        normalizedAttrs.letterSpacing = letterSpacingMeasurement.value
      }
      const sourceTypographyUnit =
        fontSizeMeasurement?.sourceUnit ??
        lineHeightMeasurement?.sourceUnit ??
        letterSpacingMeasurement?.sourceUnit
      if (sourceTypographyUnit !== undefined) {
        normalizedAttrs.sourceTypographyUnit = sourceTypographyUnit
      }
      if (fontWeight !== undefined) {
        normalizedAttrs.fontWeight = fontWeight
        normalizedAttrs.fontWeightRaw = fontWeight
      }
      if (
        fontSizeMeasurement !== undefined ||
        lineHeightMeasurement !== undefined ||
        letterSpacingMeasurement !== undefined
      ) {
        normalizedAttrs.typographyUnit = 'dp'
        normalizedAttrs.platformFontScale = this.resolveTypographyFontScale()
      }
    }

    for (const key of Object.keys(normalizedObject)) {
      if (key === '$attrs') {
        continue
      }
      normalizedObject[key] = this.normalizeTypographyInspectorPayload(normalizedObject[key])
    }
    return normalizedObject
  }

  private parseEmbeddedJsonString(value: string): InspectorValue {
    const trimmed = value.trim()
    const maybeJson =
      (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'))
    if (!maybeJson) {
      return value
    }

    try {
      const parsed = JSON.parse(trimmed) as InspectorValue
      return this.normalizeInspectorPayload(parsed)
    } catch (_error) {
      return value
    }
  }

  private captureFrameNodeRoots(): ExportViewTreeNode[] {
    const anchorNode = this.resolveAnchorNode()
    const rootNode = this.resolveTopRootNode(anchorNode)
    if (rootNode === null) {
      return []
    }
    return [this.toViewTreeNode(rootNode, null)]
  }

  private resolveAnchorNode(): FrameNode | null {
    if (this.uiContext === null || this.viewTreeAnchorUniqueId === null) {
      return null
    }
    return this.uiContext.getFrameNodeByUniqueId(this.viewTreeAnchorUniqueId)
  }

  private resolveTopRootNode(node: FrameNode | null): FrameNode | null {
    if (node === null) {
      return null
    }

    let current: FrameNode = node
    while (true) {
      const parent = current.getParent()
      if (parent === null || parent.getUniqueId() <= 0) {
        break
      }
      current = parent
    }
    return current
  }

  private toViewTreeNode(node: FrameNode, parentId: string | null): ExportViewTreeNode {
    const uniqueId = node.getUniqueId()
    const rawId = node.getId()
    const nodeId = this.normalizeNodeId(rawId, uniqueId)
    const nodeType = this.normalizeNodeType(node.getNodeType())
    const children: ExportViewTreeNode[] = []
    const count = node.getChildrenCount()
    for (let index = 0; index < count; index += 1) {
      const child = this.readChildNode(node, index)
      if (child !== null) {
        children.push(this.toViewTreeNode(child, nodeId))
      }
    }
    return {
      id: nodeId,
      parentId,
      name: nodeType,
      children
    }
  }

  private readChildNode(node: FrameNode, index: number): FrameNode | null {
    try {
      return node.getChild(index, ExpandMode.EXPAND)
    } catch (_error) {
      return node.getChild(index)
    }
  }

  private normalizeNodeId(rawId: string, uniqueId: number): string {
    const normalized = rawId.trim()
    if (normalized.length > 0) {
      return normalized
    }
    return `node-${String(uniqueId)}`
  }

  private normalizeNodeType(rawType: string): string {
    const normalized = rawType.trim()
    return normalized.length > 0 ? normalized : 'UnknownNode'
  }

  private normalizeViewTreePlatform(platform: string | undefined): Platform {
    if (platform === 'ios' || platform === 'android' || platform === 'web') {
      return platform
    }
    return 'harmony'
  }
}
